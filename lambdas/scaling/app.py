reference = "https://www.sentialabs.io/2018/08/24/Custom-ECS-Container-Instance-Scaling-Metric.html"
__copyright__ = """
    Copyright 2018 Sentia <www.sentia.nl>
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
       http://www.apache.org/licenses/LICENSE-2.0
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
"""
__license__ = "Apache 2.0"

import boto3
import os
import datetime
import dateutil
import logging


def lambda_handler(event, context):
    ecs_cluster_name = event['ecs_cluster_name']
    region_name = os.environ['AWS_REGION']
    scalability_index = event['scalability_index']

    ecs = boto3.client('ecs', region_name=region_name)
    cw = boto3.client('cloudwatch', region_name=region_name)
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)

    ##############################
    # Calculate services metrics
    services_arns = ecs.list_services(cluster=ecs_cluster_name)['serviceArns']
    services = ecs.describe_services(
        cluster=ecs_cluster_name, services=services_arns)['services']

    # Largest container requirements
    min_required_cpu_units = 0
    min_required_mem_units = 0
    # Total reservation across instances
    total_registered_cpu_units = 0
    total_registered_mem_units = 0
    # Total nominal units per instance
    cpu_units_per_instance = 0
    mem_units_per_instance = 0
    # Free space across available instances, per instance
    remaining_cpu_units_per_instance = []
    remaining_mem_units_per_instance = []
    # Schedulable largest container
    schedulable_largest_containers_by_cpu = 0
    schedulable_largest_containers_by_mem = 0

    for service in services:
        # TODO: enrich finctionality for quick scaling based on desired count,
        # or running count
        running_count = service['runningCount']
        desired_count = service['desiredCount']
        container_definitions = ecs.describe_task_definition(
            taskDefinition=service['taskDefinition']
        )['taskDefinition']['containerDefinitions']
        for container_definition in container_definitions:
            min_required_cpu_units = max(
                min_required_cpu_units, container_definition['cpu'])
            min_required_mem_units = max(
                min_required_mem_units, container_definition['memory'])

    ##############################
    # Calculate cluster metrics
    container_instance_arns = ecs.list_container_instances(
        cluster=ecs_cluster_name)['containerInstanceArns']
    container_instances = ecs.describe_container_instances(
        cluster=ecs_cluster_name,
        containerInstances=container_instance_arns)['containerInstances']

    for container_instance in container_instances:
        remaining_resources = {
            resource['name']: resource
            for resource in container_instance['remainingResources']}
        schedulable_largest_containers_by_cpu += int(
            remaining_resources['CPU']['integerValue']
            / min_required_cpu_units)
        schedulable_largest_containers_by_mem += int(
            remaining_resources['MEMORY']['integerValue']
            / min_required_mem_units)
        for resources in container_instance['registeredResources']:
            if 'CPU' in resources.values():
                total_registered_cpu_units += resources['integerValue']
            if 'MEMORY' in resources.values():
                total_registered_mem_units += resources['integerValue']
        for resources in container_instance['remainingResources']:
            if 'CPU' in resources.values():
                remaining_cpu_units_per_instance.append(
                    resources['integerValue'])
            if 'MEMORY' in resources.values():
                remaining_mem_units_per_instance.append(
                    resources['integerValue'])

    cpu_units_per_instance = total_registered_cpu_units // len(
        container_instances)
    mem_units_per_instance = total_registered_mem_units // len(
        container_instances)

    cpu_scale_in_threshold = int(
        cpu_units_per_instance / min_required_cpu_units) + scalability_index
    mem_scale_in_threshold = int(
        mem_units_per_instance / min_required_mem_units) + scalability_index

    # Check for required scaling activity
    # {"-1": "scale in", "0": "no scaling activity", "1": "scale out"}
    if min(schedulable_largest_containers_by_cpu,
           schedulable_largest_containers_by_mem) < scalability_index:
        logger.info(('A total of (CPU: %d, MEM: %d) can be scheduled based on '
                     'each metric. This is less than the scalability index '
                     '(%d)') % (
            schedulable_largest_containers_by_cpu,
            schedulable_largest_containers_by_mem,
            scalability_index))
        logger.info(('Scale out is required, but I can only update the  '
                     'metric from my point of view.'))
        requires_scaling = 1
    elif (schedulable_largest_containers_by_cpu >= cpu_scale_in_threshold and
          schedulable_largest_containers_by_mem >= mem_scale_in_threshold):
        logger.info(('A total of (CPU: %d, MEM: %d) of the largest containers '
                     ' can be scheduled based on each metric. This is larger '
                     'or equal to the threshold of (CPU: %d, MEM: %d).') % (
            schedulable_largest_containers_by_cpu,
            schedulable_largest_containers_by_mem,
            cpu_scale_in_threshold,
            mem_scale_in_threshold))
        logger.info(('Scale in is required, but I can only update the metric '
                     'from my point of view.'))
        requires_scaling = -1
    else:
        logger.info('Everything looks great. No scaling actions required.')
        requires_scaling = 0

    cw.put_metric_data(Namespace='AWS/ECS',
                       MetricData=[{
                           'MetricName': 'RequiresScaling',
                           'Dimensions': [{
                               'Name': 'ClusterName',
                               'Value': ecs_cluster_name
                           }],
                           'Timestamp': datetime.datetime.now(
                                            dateutil.tz.tzlocal()),
                           'Value': requires_scaling
                       }])

    return {}