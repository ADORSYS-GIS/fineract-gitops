# Cost Optimization Automation

This document explains the automated shutdown and startup procedures for the `dev` and `uat` environments to reduce costs outside of business hours.

## Overview

To optimize costs, we automatically shut down the `dev` and `uat` environments on weekdays during non-business hours. This process involves two main steps:

1.  **Scaling down Kubernetes resources**: The replicas of the Fineract `Rollout` resources are scaled down to 0.
2.  **Stopping RDS instances**: The AWS RDS instances for the `dev` and `uat` environments are stopped.

This process is managed by a set of Kubernetes `CronJob` resources.

## The `CronJob` Resources

The following `CronJob` resources are defined in the `apps/fineract/base/` directory:

*   `scale-down-cronjob.yaml`: This `CronJob` runs at 7 PM on weekdays and scales down the `fineract-read` `Rollout` resources in the `dev` and `uat` namespaces to 0 replicas.
*   `scale-up-cronjob.yaml`: This `CronJob` runs at 7 AM on weekdays and scales up the `fineract-read` `Rollout` resources in the `dev` and `uat` namespaces to their original number of replicas.
*   `rds-shutdown-cronjob.yaml`: This file defines two `CronJob` resources:
    *   `rds-shutdown`: This `CronJob` runs at 7 PM on weekdays and stops the `fineract-dev` and `fineract-uat` RDS instances.
    *   `rds-startup`: This `CronJob` runs at 7 AM on weekdays and starts the `fineract-dev` and `fineract-uat` RDS instances.

## Prerequisites

For the RDS shutdown and startup `CronJobs` to function correctly, the `fineract-scaler` service account must be associated with an IAM role that has the necessary permissions to stop and start RDS instances.

This can be achieved using [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html).

The IAM role should have a policy similar to the following:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "rds:StopDBInstance",
                "rds:StartDBInstance"
            ],
            "Resource": [
                "arn:aws:rds:us-east-2:123456789012:db:fineract-dev",
                "arn:aws:rds:us-east-2:123456789012:db:fineract-uat"
            ]
        }
    ]
}
```

Replace `us-east-2` with your AWS region and `123456789012` with your AWS account ID.

## How to Configure the Schedule

The schedule for the `CronJobs` is defined in the `schedule` field of each `CronJob` resource. The format is a standard cron expression.

To change the schedule, simply update the `schedule` field in the corresponding `CronJob` manifest and apply the changes.

For example, to change the shutdown time to 8 PM, you would update the `schedule` field in `scale-down-cronjob.yaml` and `rds-shutdown-cronjob.yaml` to `0 20 * * 1-5`.
