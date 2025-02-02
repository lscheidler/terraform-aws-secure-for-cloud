# Secure for Cloud - Organizational Cloudtrail+SNS with S3 in a different account

## Use-Case explanation

**Current User Setup**

- Secure for Cloud **organizational** setup, meaning
  - Pre-existing management Account level AWS Organizational Cloudtrail
  - Cloudtrail has SNS activated
- In this use-case, the **S3 bucket is not in the management account** of the organization, but on a different logging
  account
- A pre-existing compute **cluster available** (EKS or ECS) for Sysdig workload to deployment
- Permission provisioning will be performed **manually** with several **IAM Roles**

**Sysdig Secure for Cloud [Features](https://docs.sysdig.com/en/docs/installation/sysdig-secure-for-cloud/)**
- Threat-Detection
- Posture; Compliance + Identity Access Management
<br/><br/>


## Infrastructure Setup

As a quick summary we'll have
- Organizational **Management** Account
  - Pre-Existing organizational-cloudtrail with SNS activated
- Member Account - **Logs Account**
  - Pre-Existing Cloudtrail-S3 bucket
  - We will create a specific role for cross-account S3 access enablement
- Member Account - **Sysdig Compute Account**
  - Pre-Existing EKS/ECS cluster for Sysdig for Cloud compute deployment (cloud-connector)
  - We will create a topic for Cloudtrail-SNS-SQS wiring, from organizational cloudtrail into cloud-connector compute module
- **Member Account(s)**
  - Sysdig Compliance Role (aws:SecurityAudit policy)

Note:
- All event ingestion resource (cloudtrail-sns, and cloudtrail-s3 bucket) live in same `AWS_REGION` AWS region.
  Otherwise, contact us, so we can alleviate this limitation.

![three-way k8s setup](./resources/org-three-way-with-sns.png)


## Suggested building-blocks

We suggest to
- start with Cloud-Connector module required infrastructure wiring and deployment; this will cover threat-detection
  side
- then move on to Compliance role setup if required
  <br/><br/>

## Prepare **EKS/ECS SysdigComputeRole**

In further steps, we will deploy Sysdig compute workload inside an EKS/ECS cluster.

We are going to need a `SysdigComputeRole` (attached to the compute service), to configure some permissions to be
able to fetch the required data.<br/>
Create this role in your cluster, and enable it to be used from within. Save the `ARN_SYSDIG_COMPUTE_ROLE`

- for **EKS** cluster, use IAM authentication role mapping setup, or if you want to
  quickly test it, just make use of the `eks_nodes` role generated by default in EKS.
- for **ECS**  allow Trust relationship for ECS-Task usage
  ```json
  {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Sid": "",
              "Effect": "Allow",
              "Principal": {
                  "Service": "ecs-tasks.amazonaws.com"
              },
              "Action": "sts:AssumeRole"
          }
      ]
  }
  ```

<br/><br/>

## Cloud-Connector wiring: Organizational Cloudtrail S3 + SNS - SQS

<!--

all in same region
management account - cloudtrail (no kms for quick test)
log archive account - s3, sns, sqs

0.1 Provision an S3 bucket in the selected region and allow cloudtrail access
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Statement1",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "S3_ARN/*"
        },
        {
            "Sid": "Statement2",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:GetBucketAcl",
            "Resource": "S3_ARN"
        }
    ]
}

0.2. Provision the s3 bucket sns event notification. Need to add permissions to SNS
{
      "Sid": "AllowS3ToPublishSNS",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": [
        "SNS:Publish"
      ],
      "Resource": "ARN_SNS"
    }
-->

<!--
    - If SQS and EKS cluster are within the same account, you will only need to give **permissions** to either SysdigCompute IAM role or SQS.
<br/>[Otherwise, you will need to provide permissions for both](https://aws.amazon.com/premiumsupport/knowledge-center/sqs-accessdenied-errors/#Amazon_SQS_access_policy_and_IAM_policy).
<br/>Use following snipped if required.
```txt
{
"Sid": "AllowSysdigProcessSQS",
"Effect": "Allow",
"Principal": {
"AWS": "<SYSDIG_COMPUTE_ROLE_ARN>"
},
"Action": [
"SQS:ReceiveMessage",
"SQS:DeleteMessage"
],
"Resource": "<CLOUDTRAIL_SNS_SQS_ARN>"
}
```
-->


We will leverage Secure for Cloud - cloudtrail ingestion, in order to consume organizational events.
For that, we will need to prepare an SQS to ingest the events, and the Cloudtrail-S3 bucket, in order to allow
cross-account read.

1. Verify that your Organizational Cloudtrail has the **Cloudtrail-SNS notification activated** within same account and
   region.<br/><br/>

2. In your organization, where the ECS/EKS cluster is, will be the **member account** `SYSDIG_ACCOUNT_ID`.
   <br/>Here, besides the compute cluster, where Sysdig compute workload will be deployed, we will create an SQS
   topic to ingest Cloudtrail events.<br/><br/>

3. In `SYSDIG_ACCOUNT_ID`, create an **SQS queue** (in the same region as the SNS and ECS/EKS cluster).
  - Default queue parametrization is enough.
  - Subscribe the Cloudtrail-SNS topic to it.
  - Due to cross-account limitations, you may need to enable `SNS:Subscribe` permissions on the queue first
    ```json
    {
      "Sid": "AllowCrossAccountSNSSubscription",
      "Effect": "Allow",
      "Principal": {
        "AWS": "<ARN_SUBSCRIPTION_ACTION_USER>"
      },
      "Action": "sns:Subscribe",
      "Resource": "<ARN_CLOUDTRAIL_SNS>"
    }
    ```
  - Save `SYSDIG_CLOUDTRAIL_SNS_SQS_URL` and `ARN_CLOUDTRAIL_SNS_SQS` for later<br/><br/>

4. Configure **Cross-Account S3 access-credentials**
  - In the organizational account where Cloudtrail-S3 bucket is placed, create a new `SysdigS3AccessRole` role to
    handle following permissions and save `ARN_ROLE_SYSDIG_S3_ACCESS`
    ```json
    {
        "Sid": "AllowSysdigReadS3",
        "Effect": "Allow",
        "Action": [
          "s3:GetObject"
        ],
        "Resource": "<ARN_CLOUDTRAIL_S3>/*"
    }
    ```
  - Now we will need to perform same permissions setup on the S3 bucket. Add following Statement to the Bucket policy
     ```json
     {
         "Sid": "AllowSysdigReadS3",
         "Effect": "Allow",
         "Principal": {
           "AWS": "<ARN_ROLE_SYSDIG_S3_ACCESS>"
         },
         "Action": "s3:GetObject",
         "Resource": "<ARN_CLOUDTRAIL_S3>/*"
      }
       ```
  - Last step, is to allow cross-account `assumeRole` Trust Relationship, for Sysdig Compute role to be able to make
    use of this `SysdigS3AccessRole`
    ```json
    {
    "Sid": "AllowSysdigAssumeRole",
    "Effect": "Allow",
    "Principal": {
    "AWS": "<ARN_SYSDIG_COMPUTE_ROLE>"
    },
    "Action": "sts:AssumeRole"
    }
    ```
<br/><br/>



## Secure for Cloud Compute Deployment

In the `SYSDIG_ACCOUNT_ID` account.

We will setup the `SysdigComputeRole`, to be able to perform required actions by Secure for Cloud
compute; work with the SQS and access S3 resources (this last one via assumeRole).

```json
{
    "Version": "2012-10-17",
    "Statement": [
	    {
            "Effect": "Allow",
            "Action": [
                "SQS:ReceiveMessage",
                "SQS:DeleteMessage"
            ],
            "Resource": "<ARN_CLOUDTRAIL_SNS_SQS>"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sts:AssumeRole"
            ],
            "Resource": "<ARN_SYSDIG_S3_ACCESS_ROLE>"
        }
    ]
}
```

Now we will deploy the compute component, depending on the compute service

#### A) EKS


<!--
1. Kubernetes **Credentials** creation
   - This step is not really required if Kubernetes role binding is properly configured for the deployment, with an
     IAM role with required permissions listed in following points.
   - Otherwise, we will create an AWS user `SYSDIG_K8S_USER_ARN`, with `SYSDIG_K8S_ACCESS_KEY_ID` and
     `SYSDIG_K8S_SECRET_ACCESS_KEY`, in order to give Kubernetes compute permissions to be able to handle S3 and SQS operations
   - Secure for Cloud [does not manage IAM key-rotation, but find some suggestions to rotate access-key](https://github.com/sysdiglabs/terraform-aws-secure-for-cloud/tree/master/modules/infrastructure/permissions/iam-user#access-key-rotation)<br/><br/>
-->


If using Kubernetes, we will make use of the [Sysdig cloud-connector helm chart](https://charts.sysdig.com/charts/cloud-connector/) component.
<br/>Locate your `<SYSDIG_SECURE_ENDPOINT>` and `<SYSDIG_SECURE_API_TOKEN>`.<br/> [Howto fetch ApiToken](https://docs.sysdig.com/en/docs/administration/administration-settings/user-profile-and-password/retrieve-the-sysdig-api-token)

Provided the following `values.yaml` template
```yaml
sysdig:
  url: "https://secure.sysdig.com"
  secureAPIToken: "SYSDIG_API_TOKEN"
telemetryDeploymentMethod: "helm_aws_k8s_org"		# not required but would help us
aws:
    region: <SQS-AWS-REGION>
ingestors:
    - cloudtrail-sns-sqs:
        queueURL:"<URL_CLOUDTRAIL_SNS_SQS>"             # step 3
        assumeRole:"<ARN_ROLE_SYSDIG_S3_ACCESS>"        # step 4
```

We will install it
```shell
$ helm upgrade --install --create-namespace -n sysdig-cloud-connector sysdig-cloud-connector sysdig/cloud-connector -f values.yaml
```

Test it
```shell
$ kubectl logs -f -n sysdig-cloud-connector deployment/sysdig-cloud-connector
```

And if desired uninstall it
```shell
$ helm uninstall -n sysdig-cloud-connector sysdig-cloud-connector
```

#### B) ECS

If using , AWS ECS (Elastic Container Service), we will create a new Fargate Task.

- TaskRole: Use previously created `SysdigComputeRole`
- Task memory (GB): 0.5 and Task CPU (vCPU: 0.25 will suffice
- Container definition
  - Image: `quay.io/sysdig/cloud-connector:latest`
  - Port Mappings; bind port 5000 tcp protocol
  - Environment variables
    - SECURE_URL
    - SECURE_API_TOKEN
    - CONFIG:  A base64 encoded configuration of the cloud-connector service
    ```yaml
    logging: info
    rules: []
    ingestors:
        - cloudtrail-sns-sqs:
            queueURL: <URL_CLOUDTRAIL_SNS_SQS>
            assumeRole: <ARN_ROLE_SYSDIG_S3_ACCESS>
    ```
<!--

AWS Systems Manager
Application Manager
CustomGroup: iru


AWS::SSM::Parameter
Type: SecureString
Data type: text

In ContainerDefinition, secrets
- SECURE_API_TOKEN, `secretName`


ExecutionRole
{
"Version": "2012-10-17",
"Statement": [
{
"Sid": "",
"Effect": "Allow",
"Action": "ssm:GetParameters",
"Resource": "arn:aws:ssm:eu-west-3:**:parameter/**"
}
]
}
-->


## Testing

Check within Sysdig Secure
- Integrations > Cloud Accounts
- Insights > Cloud Activity

- [Official Docs Check Guide](https://docs.sysdig.com/en/docs/installation/sysdig-secure-for-cloud/deploy-sysdig-secure-for-cloud-on-gcp/#confirm-the-services-are-working)
- [Forcing events](https://github.com/sysdiglabs/terraform-google-secure-for-cloud#forcing-events)
