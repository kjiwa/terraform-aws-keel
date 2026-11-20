import datetime
import json

import pytest

import ami_updater

NOW = datetime.datetime(2026, 11, 19, 12, 0, tzinfo=datetime.timezone.utc)
ASG = "bots"
LT = {"arm64": "lt-arm", "x86_64": "lt-x86"}
PARAMETERS = {"arm64": "/p/arm64", "x86_64": "/p/x86_64"}
OLD = {"arm64": "ami-old-arm", "x86_64": "ami-old-x86"}
NEW = {"arm64": "ami-new-arm", "x86_64": "ami-new-x86"}


def days_ago(days):
    return (NOW - datetime.timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def config(**overrides):
    values = {
        "asg_name": ASG,
        "launch_template_ids": LT,
        "ssm_parameters": PARAMETERS,
        "min_age_hours": 24,
        "max_age_days": 14,
        "preferences": {"min_healthy_percentage": 100, "max_healthy_percentage": 150, "instance_warmup": 60},
        "alarm_names": [],
        "dry_run": False,
    }
    values.update(overrides)
    return ami_updater.Config(**values)


class FakeSsm:
    def __init__(self, amis):
        self.amis = amis

    def get_parameter(self, Name):
        return {"Parameter": {"Value": self.amis[Name]}}


class FakeEc2:
    def __init__(self, latest, pinned=None, created=None, instances=None):
        self.latest = dict(latest)
        self.pinned = dict(pinned or latest)
        self.created = created or {}
        self.instances = instances or {}
        self.versions = {lt: 3 for lt in LT.values()}
        self.new_versions = []
        self.gone = set()

    def describe_launch_template_versions(self, LaunchTemplateId, Versions):
        arch = {v: k for k, v in LT.items()}[LaunchTemplateId]
        out = []
        for version in Versions:
            if version == "$Latest":
                out.append({"VersionNumber": self.versions[LaunchTemplateId], "LaunchTemplateData": {"ImageId": self.latest[arch]}})
            else:
                out.append({"VersionNumber": int(version), "LaunchTemplateData": {"ImageId": self.pinned[arch]}})
        return {"LaunchTemplateVersions": out}

    def describe_images(self, ImageIds):
        if any(i in self.gone for i in ImageIds):
            raise MissingImage()
        return {"Images": [{"ImageId": i, "CreationDate": self.created[i]} for i in ImageIds if i in self.created]}

    def create_launch_template_version(self, **kwargs):
        self.new_versions.append(kwargs)
        arch = {v: k for k, v in LT.items()}[kwargs["LaunchTemplateId"]]
        self.versions[kwargs["LaunchTemplateId"]] += 1
        self.latest[arch] = kwargs["LaunchTemplateData"]["ImageId"]
        return {"LaunchTemplateVersion": {"VersionNumber": self.versions[kwargs["LaunchTemplateId"]]}}

    def describe_instances(self, InstanceIds):
        return {"Reservations": [{"Instances": [{"InstanceId": i, "ImageId": self.instances[i]} for i in InstanceIds]}]}


def mixed_policy(version):
    spec = lambda lt: {"LaunchTemplateId": lt, "LaunchTemplateName": "n", "Version": version}
    return {
        "LaunchTemplate": {
            "LaunchTemplateSpecification": spec(LT["x86_64"]),
            "Overrides": [
                {"InstanceType": "t3a.nano", "LaunchTemplateSpecification": spec(LT["x86_64"])},
                {"InstanceType": "t4g.nano", "LaunchTemplateSpecification": spec(LT["arm64"])},
            ],
        },
        "InstancesDistribution": {"SpotAllocationStrategy": "price-capacity-optimized", "OnDemandBaseCapacity": 0},
    }


class MissingImage(Exception):
    response = {"Error": {"Code": "InvalidAMIID.NotFound"}}


class FakeAutoscaling:
    def __init__(self, instance_ids=(), policy=None, launch_template=None, refreshes=()):
        self.group = {"AutoScalingGroupName": ASG, "Instances": [{"InstanceId": i, "LifecycleState": "InService"} for i in instance_ids]}
        if launch_template:
            self.group["LaunchTemplate"] = launch_template
        else:
            self.group["MixedInstancesPolicy"] = policy or mixed_policy("3")
        self.refreshes = list(refreshes)
        self.updates = []
        self.started = []

    def describe_auto_scaling_groups(self, AutoScalingGroupNames):
        return {"AutoScalingGroups": [self.group]}

    def describe_instance_refreshes(self, AutoScalingGroupName):
        return {"InstanceRefreshes": [{"Status": s} for s in self.refreshes]}

    def update_auto_scaling_group(self, **kwargs):
        self.updates.append(kwargs)

    def start_instance_refresh(self, **kwargs):
        self.started.append(kwargs)
        return {"InstanceRefreshId": "refresh-1"}


class FakeCloudwatch:
    def __init__(self, alarms=None):
        self.alarms = alarms or {}
        self.metrics = []

    def describe_alarms(self, AlarmNames):
        return {"MetricAlarms": [{"AlarmName": n, "StateValue": self.alarms.get(n, "OK")} for n in AlarmNames]}

    def put_metric_data(self, **kwargs):
        self.metrics.append(kwargs)


def run(cfg=None, ec2=None, autoscaling=None, cloudwatch=None, ssm=None):
    ec2 = ec2 or FakeEc2(OLD, created={**{a: days_ago(2) for a in NEW.values()}, **{a: days_ago(10) for a in OLD.values()}})
    autoscaling = autoscaling or FakeAutoscaling()
    cloudwatch = cloudwatch or FakeCloudwatch()
    ssm = ssm or FakeSsm({PARAMETERS[a]: NEW[a] for a in NEW})
    result = ami_updater.run(cfg or config(), ec2, autoscaling, ssm, cloudwatch, NOW)
    return result, ec2, autoscaling, cloudwatch


def test_writes_a_version_per_architecture_when_the_release_is_old_enough():
    _, ec2, _, _ = run()
    assert sorted((v["LaunchTemplateId"], v["LaunchTemplateData"]["ImageId"]) for v in ec2.new_versions) == [
        ("lt-arm", "ami-new-arm"),
        ("lt-x86", "ami-new-x86"),
    ]
    assert all(v["SourceVersion"] == "3" for v in ec2.new_versions)


def test_versions_carry_no_description():
    # The provider reads the description of the latest version, so a description
    # here would show up as drift in the consumer's launch template.
    _, ec2, _, _ = run()
    assert all("VersionDescription" not in v for v in ec2.new_versions)


def test_waits_while_the_release_is_younger_than_min_age_hours():
    ec2 = FakeEc2(OLD, created={**{a: (NOW - datetime.timedelta(hours=23)).strftime("%Y-%m-%dT%H:%M:%S.000Z") for a in NEW.values()}, **{a: days_ago(10) for a in OLD.values()}})
    _, ec2, autoscaling, _ = run(ec2=ec2)
    assert ec2.new_versions == [] and autoscaling.updates == []


def test_writes_nothing_when_the_template_already_has_the_release():
    ec2 = FakeEc2(NEW, created={a: days_ago(2) for a in NEW.values()})
    _, ec2, autoscaling, _ = run(ec2=ec2)
    assert ec2.new_versions == [] and autoscaling.updates == []


def test_group_follows_the_new_versions_in_a_mixed_policy():
    _, _, autoscaling, _ = run()
    (update,) = autoscaling.updates
    policy = update["MixedInstancesPolicy"]
    specs = [policy["LaunchTemplate"]["LaunchTemplateSpecification"]] + [o["LaunchTemplateSpecification"] for o in policy["LaunchTemplate"]["Overrides"]]
    assert [s["Version"] for s in specs] == ["4", "4", "4"]
    assert all("LaunchTemplateName" not in s for s in specs)
    assert policy["InstancesDistribution"]["SpotAllocationStrategy"] == "price-capacity-optimized"
    assert update["AutoScalingGroupName"] == ASG


def test_group_follows_the_new_version_of_a_plain_launch_template():
    asg = FakeAutoscaling(launch_template={"LaunchTemplateId": LT["x86_64"], "LaunchTemplateName": "n", "Version": "3"})
    cfg = config(launch_template_ids={"x86_64": LT["x86_64"]}, ssm_parameters={"x86_64": "/p/x86_64"})
    _, _, autoscaling, _ = run(cfg=cfg, autoscaling=asg)
    assert autoscaling.updates == [{"AutoScalingGroupName": ASG, "LaunchTemplate": {"LaunchTemplateId": LT["x86_64"], "Version": "4"}}]


def test_group_is_left_alone_when_only_the_user_data_changed():
    pinned = {"arm64": NEW["arm64"], "x86_64": NEW["x86_64"]}
    ec2 = FakeEc2(NEW, pinned=pinned, created={a: days_ago(2) for a in NEW.values()})
    ec2.versions = {lt: 5 for lt in LT.values()}
    _, _, autoscaling, _ = run(ec2=ec2)
    assert autoscaling.updates == []


def test_group_catches_up_when_an_earlier_run_wrote_the_version_but_not_the_pin():
    ec2 = FakeEc2(NEW, pinned=OLD, created={**{a: days_ago(2) for a in NEW.values()}, **{a: days_ago(10) for a in OLD.values()}})
    _, ec2, autoscaling, _ = run(ec2=ec2)
    assert ec2.new_versions == [] and len(autoscaling.updates) == 1


def test_refreshes_when_a_running_image_is_older_than_the_limit_and_a_newer_one_is_targeted():
    created = {**{a: days_ago(2) for a in NEW.values()}, "ami-ancient": days_ago(15)}
    ec2 = FakeEc2(OLD, created=created, instances={"i-1": "ami-ancient"})
    result, _, autoscaling, _ = run(ec2=ec2, autoscaling=FakeAutoscaling(["i-1"]))
    assert autoscaling.started == [
        {
            "AutoScalingGroupName": ASG,
            "Strategy": "Rolling",
            "Preferences": {"MinHealthyPercentage": 100, "MaxHealthyPercentage": 150, "InstanceWarmup": 60},
        }
    ]
    assert result["refresh"] == "refresh-1"


def test_omits_the_warmup_when_none_is_set():
    created = {**{a: days_ago(2) for a in NEW.values()}, "ami-ancient": days_ago(15)}
    ec2 = FakeEc2(OLD, created=created, instances={"i-1": "ami-ancient"})
    cfg = config(preferences={"min_healthy_percentage": 100, "max_healthy_percentage": 200, "instance_warmup": None})
    _, _, autoscaling, _ = run(cfg=cfg, ec2=ec2, autoscaling=FakeAutoscaling(["i-1"]))
    assert autoscaling.started[0]["Preferences"] == {"MinHealthyPercentage": 100, "MaxHealthyPercentage": 200}


def test_keeps_instances_whose_image_is_under_the_limit():
    created = {**{a: days_ago(2) for a in NEW.values()}, "ami-recent": days_ago(13)}
    ec2 = FakeEc2(OLD, created=created, instances={"i-1": "ami-recent"})
    _, _, autoscaling, _ = run(ec2=ec2, autoscaling=FakeAutoscaling(["i-1"]))
    assert autoscaling.started == []


def test_does_not_refresh_onto_the_image_it_already_runs():
    created = {"ami-ancient": days_ago(15)}
    ec2 = FakeEc2({"arm64": "ami-ancient", "x86_64": "ami-ancient"}, created=created, instances={"i-1": "ami-ancient"})
    ssm = FakeSsm({PARAMETERS["arm64"]: "ami-ancient", PARAMETERS["x86_64"]: "ami-ancient"})
    _, _, autoscaling, _ = run(ec2=ec2, autoscaling=FakeAutoscaling(["i-1"]), ssm=ssm)
    assert autoscaling.started == []


@pytest.mark.parametrize("status", ["Pending", "InProgress", "Cancelling", "RollbackInProgress", "Baking"])
def test_skips_everything_while_a_refresh_is_running(status):
    created = {**{a: days_ago(2) for a in NEW.values()}, "ami-ancient": days_ago(15)}
    ec2 = FakeEc2(OLD, created=created, instances={"i-1": "ami-ancient"})
    result, ec2, autoscaling, _ = run(ec2=ec2, autoscaling=FakeAutoscaling(["i-1"], refreshes=["Successful", status]))
    assert result["skipped"] == "refresh in progress"
    assert ec2.new_versions == [] and autoscaling.updates == [] and autoscaling.started == []


def test_skips_everything_while_a_named_alarm_is_in_alarm():
    cfg = config(alarm_names=["site-down", "group-size"])
    result, ec2, autoscaling, _ = run(cfg=cfg, cloudwatch=FakeCloudwatch({"group-size": "ALARM"}))
    assert result["skipped"] == "alarm in ALARM: group-size"
    assert ec2.new_versions == [] and autoscaling.updates == []


def test_finished_refreshes_and_quiet_alarms_do_not_block():
    cfg = config(alarm_names=["site-down"])
    _, ec2, _, _ = run(cfg=cfg, autoscaling=FakeAutoscaling(refreshes=["Successful", "Failed", "Cancelled"]))
    assert len(ec2.new_versions) == 2


def test_publishes_the_oldest_running_image_age():
    created = {**{a: days_ago(2) for a in NEW.values()}, "ami-a": days_ago(5), "ami-b": days_ago(9)}
    ec2 = FakeEc2(OLD, created=created, instances={"i-1": "ami-a", "i-2": "ami-b"})
    _, _, _, cloudwatch = run(ec2=ec2, autoscaling=FakeAutoscaling(["i-1", "i-2"]))
    (call,) = cloudwatch.metrics
    assert call["Namespace"] == "AmiUpdater"
    (datum,) = call["MetricData"]
    assert datum["MetricName"] == "AmiAgeDays" and datum["Dimensions"] == [{"Name": "AutoScalingGroupName", "Value": ASG}]
    assert datum["Value"] == pytest.approx(9.0)


def test_publishes_nothing_without_running_instances():
    _, _, _, cloudwatch = run()
    assert cloudwatch.metrics == []


def test_publishes_the_age_even_while_a_refresh_runs():
    created = {"ami-a": days_ago(30), **{a: days_ago(2) for a in NEW.values()}}
    ec2 = FakeEc2(OLD, created=created, instances={"i-1": "ami-a"})
    _, _, _, cloudwatch = run(ec2=ec2, autoscaling=FakeAutoscaling(["i-1"], refreshes=["InProgress"]))
    assert cloudwatch.metrics[0]["MetricData"][0]["Value"] == pytest.approx(30.0)


def test_dry_run_changes_nothing_and_reports_what_it_would_do():
    created = {**{a: days_ago(2) for a in NEW.values()}, "ami-ancient": days_ago(15)}
    ec2 = FakeEc2(OLD, created=created, instances={"i-1": "ami-ancient"})
    result, ec2, autoscaling, _ = run(cfg=config(dry_run=True), ec2=ec2, autoscaling=FakeAutoscaling(["i-1"]))
    assert ec2.new_versions == [] and autoscaling.updates == [] and autoscaling.started == []
    assert result["dry_run"] is True
    assert result["new_versions"] == {} and sorted(result["would_write"]) == ["arm64", "x86_64"]
    assert result["pin"] is True and result["refresh"] == "dry-run"


def test_config_reads_the_environment():
    env = {
        "ASG_NAME": ASG,
        "LAUNCH_TEMPLATE_IDS": json.dumps(LT),
        "SSM_PARAMETERS": json.dumps(PARAMETERS),
        "MIN_AGE_HOURS": "24",
        "MAX_AGE_DAYS": "14",
        "PREFERENCES": json.dumps({"min_healthy_percentage": 100, "max_healthy_percentage": 150, "instance_warmup": None}),
        "ALARM_NAMES": json.dumps(["a"]),
        "DRY_RUN": "true",
    }
    cfg = ami_updater.Config.from_env(env)
    assert cfg.max_age_days == 14 and cfg.min_age_hours == 24 and cfg.dry_run is True and cfg.alarm_names == ["a"]
    assert cfg.preferences["instance_warmup"] is None


def test_a_deregistered_running_image_is_skipped_and_the_rest_still_counts():
    created = {**{a: days_ago(2) for a in NEW.values()}, "ami-b": days_ago(9)}
    ec2 = FakeEc2(OLD, created=created, instances={"i-1": "ami-gone", "i-2": "ami-b"})
    ec2.gone = {"ami-gone"}
    result, _, autoscaling, cloudwatch = run(ec2=ec2, autoscaling=FakeAutoscaling(["i-1", "i-2"]))
    assert cloudwatch.metrics[0]["MetricData"][0]["Value"] == pytest.approx(9.0)
    assert autoscaling.started == [] and "skipped" not in result


def test_a_template_the_group_does_not_use_fails_before_anything_is_written():
    cfg = config(launch_template_ids={**LT, "riscv": "lt-unused"}, ssm_parameters={**PARAMETERS, "riscv": "/p/riscv"})
    ec2 = FakeEc2(OLD, created={a: days_ago(2) for a in NEW.values()})
    with pytest.raises(ValueError, match="lt-unused"):
        ami_updater.run(cfg, ec2, FakeAutoscaling(), FakeSsm({PARAMETERS[a]: NEW[a] for a in NEW}), FakeCloudwatch(), NOW)
    assert ec2.new_versions == []
