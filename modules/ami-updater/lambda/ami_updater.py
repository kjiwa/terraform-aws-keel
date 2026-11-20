"""Keeps an Auto Scaling group's launch templates on the newest Amazon Linux AMI.

Each run writes a launch template version when the SSM parameter's AMI has
been out for min_age_hours and differs from the template's latest version,
points the group at the latest versions, and starts an instance refresh only
when a running instance's AMI is over max_age_days old and a newer one is
targeted. The refresh uses the group's own preferences and launch hook, so it
replaces instances as a Terraform-triggered one does.
"""

import copy
import dataclasses
import datetime
import json
import os

NAMESPACE = "AmiUpdater"
METRIC = "AmiAgeDays"
LIVE_STATES = {"InService", "Pending", "Pending:Wait", "Pending:Proceed"}
REFRESHING = {"Pending", "InProgress", "Cancelling", "RollbackInProgress", "Baking"}
MISSING_IMAGE_CODES = {"InvalidAMIID.NotFound", "InvalidAMIID.Unavailable"}


@dataclasses.dataclass
class Config:
    asg_name: str
    launch_template_ids: dict
    ssm_parameters: dict
    min_age_hours: float
    max_age_days: float
    preferences: dict
    alarm_names: list
    dry_run: bool

    @classmethod
    def from_env(cls, env):
        return cls(
            asg_name=env["ASG_NAME"],
            launch_template_ids=json.loads(env["LAUNCH_TEMPLATE_IDS"]),
            ssm_parameters=json.loads(env["SSM_PARAMETERS"]),
            min_age_hours=float(env["MIN_AGE_HOURS"]),
            max_age_days=float(env["MAX_AGE_DAYS"]),
            preferences=json.loads(env["PREFERENCES"]),
            alarm_names=json.loads(env["ALARM_NAMES"]),
            dry_run=env["DRY_RUN"] == "true",
        )


def _age(created, now):
    return now - datetime.datetime.fromisoformat(created)


def _is_missing_image(error):
    return getattr(error, "response", {}).get("Error", {}).get("Code") in MISSING_IMAGE_CODES


def _image_ages(ec2, image_ids, now):
    """Age per image. An image that can no longer be described is left out: its age is unknown, so it never forces a refresh."""
    ages = {}
    for image_id in sorted(set(image_ids)):
        try:
            images = ec2.describe_images(ImageIds=[image_id])["Images"]
        except Exception as error:
            if not _is_missing_image(error):
                raise
            print(json.dumps({"unknown_image_age": image_id}))
            continue
        ages.update({i["ImageId"]: _age(i["CreationDate"], now) for i in images})
    return ages


def _specs(group):
    if "MixedInstancesPolicy" in group:
        template = group["MixedInstancesPolicy"]["LaunchTemplate"]
        return [template["LaunchTemplateSpecification"]] + [o["LaunchTemplateSpecification"] for o in template.get("Overrides", []) if "LaunchTemplateSpecification" in o]
    return [group["LaunchTemplate"]]


def _pinned_version(group, template_id):
    return next(s["Version"] for s in _specs(group) if s["LaunchTemplateId"] == template_id)


def _latest(ec2, template_id):
    version = ec2.describe_launch_template_versions(LaunchTemplateId=template_id, Versions=["$Latest"])["LaunchTemplateVersions"][0]
    return version["VersionNumber"], version["LaunchTemplateData"]["ImageId"]


def _pinned_image(ec2, template_id, version):
    return ec2.describe_launch_template_versions(LaunchTemplateId=template_id, Versions=[version])["LaunchTemplateVersions"][0]["LaunchTemplateData"]["ImageId"]


def _blocker(config, autoscaling, cloudwatch):
    refreshes = autoscaling.describe_instance_refreshes(AutoScalingGroupName=config.asg_name)["InstanceRefreshes"]
    if any(r["Status"] in REFRESHING for r in refreshes):
        return "refresh in progress"
    if config.alarm_names:
        alarms = cloudwatch.describe_alarms(AlarmNames=config.alarm_names)["MetricAlarms"]
        firing = [a["AlarmName"] for a in alarms if a["StateValue"] == "ALARM"]
        if firing:
            return "alarm in ALARM: " + ", ".join(firing)
    return None


def _running_images(ec2, group):
    ids = [i["InstanceId"] for i in group["Instances"] if i["LifecycleState"] in LIVE_STATES]
    if not ids:
        return {}
    reservations = ec2.describe_instances(InstanceIds=ids)["Reservations"]
    return {i["InstanceId"]: i["ImageId"] for r in reservations for i in r["Instances"]}


def _publish_age(cloudwatch, config, ages):
    if not ages:
        return
    cloudwatch.put_metric_data(
        Namespace=NAMESPACE,
        MetricData=[
            {
                "MetricName": METRIC,
                "Dimensions": [{"Name": "AutoScalingGroupName", "Value": config.asg_name}],
                "Value": max(a.total_seconds() for a in ages) / 86400,
                "Unit": "None",
            }
        ],
    )


def _write_versions(config, ec2, ssm, now):
    """Returns the latest (version, image) per template, the versions written per architecture, and the architectures a dry run would write."""
    latest = {}
    written = {}
    planned = []
    for arch, template_id in config.launch_template_ids.items():
        version, image = _latest(ec2, template_id)
        target = ssm.get_parameter(Name=config.ssm_parameters[arch])["Parameter"]["Value"]
        released = _image_ages(ec2, [target], now).get(target)
        if target != image and released is not None and released >= datetime.timedelta(hours=config.min_age_hours):
            if config.dry_run:
                planned.append(arch)
            else:
                response = ec2.create_launch_template_version(
                    LaunchTemplateId=template_id,
                    SourceVersion=str(version),
                    LaunchTemplateData={"ImageId": target},
                )
                version = response["LaunchTemplateVersion"]["VersionNumber"]
                written[arch] = version
            image = target
        latest[template_id] = (version, image)
    return latest, written, planned


def _stale_pins(ec2, group, latest):
    return {
        template_id: str(version)
        for template_id, (version, image) in latest.items()
        if _pinned_image(ec2, template_id, _pinned_version(group, template_id)) != image
    }


def _group_update(group, versions):
    update = {"AutoScalingGroupName": group["AutoScalingGroupName"]}
    if "MixedInstancesPolicy" in group:
        update["MixedInstancesPolicy"] = copy.deepcopy(group["MixedInstancesPolicy"])
    else:
        update["LaunchTemplate"] = copy.deepcopy(group["LaunchTemplate"])
    for spec in _specs(update):
        spec.pop("LaunchTemplateName", None)
        if spec["LaunchTemplateId"] in versions:
            spec["Version"] = versions[spec["LaunchTemplateId"]]
    return update


def _refresh_preferences(preferences):
    result = {
        "MinHealthyPercentage": preferences["min_healthy_percentage"],
        "MaxHealthyPercentage": preferences["max_healthy_percentage"],
    }
    if preferences.get("instance_warmup") is not None:
        result["InstanceWarmup"] = preferences["instance_warmup"]
    return result


def _needs_refresh(config, instance_images, ages, targets):
    limit = datetime.timedelta(days=config.max_age_days)
    return any(ages.get(image) is not None and ages[image] > limit and image not in targets for image in instance_images.values())


def _check_templates(config, group):
    used = {s["LaunchTemplateId"] for s in _specs(group)}
    unused = sorted(set(config.launch_template_ids.values()) - used)
    if unused:
        raise ValueError(f"group {config.asg_name} does not use launch template {', '.join(unused)}")


def run(config, ec2, autoscaling, ssm, cloudwatch, now):
    group = autoscaling.describe_auto_scaling_groups(AutoScalingGroupNames=[config.asg_name])["AutoScalingGroups"][0]
    _check_templates(config, group)
    instance_images = _running_images(ec2, group)
    ages = _image_ages(ec2, instance_images.values(), now)
    _publish_age(cloudwatch, config, list(ages.values()))

    blocker = _blocker(config, autoscaling, cloudwatch)
    if blocker:
        return {"skipped": blocker}

    latest, written, planned = _write_versions(config, ec2, ssm, now)
    pins = _stale_pins(ec2, group, latest)
    if pins and not config.dry_run:
        autoscaling.update_auto_scaling_group(**_group_update(group, pins))

    refresh = None
    if _needs_refresh(config, instance_images, ages, {image for _, image in latest.values()}):
        if config.dry_run:
            refresh = "dry-run"
        else:
            refresh = autoscaling.start_instance_refresh(
                AutoScalingGroupName=config.asg_name,
                Strategy="Rolling",
                Preferences=_refresh_preferences(config.preferences),
            )["InstanceRefreshId"]

    return {"dry_run": config.dry_run, "new_versions": written, "would_write": planned, "pin": bool(pins), "refresh": refresh}


def handler(event, context):
    import boto3

    result = run(
        Config.from_env(os.environ),
        boto3.client("ec2"),
        boto3.client("autoscaling"),
        boto3.client("ssm"),
        boto3.client("cloudwatch"),
        datetime.datetime.now(datetime.timezone.utc),
    )
    print(json.dumps(result))
    return result
