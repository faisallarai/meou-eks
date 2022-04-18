## Author: Issaka Faisal

## Getting Started.

<a name="One"></a>

### Prerequisite:

1. kubectl
2. awscli
3. AWS

<a name="Two"></a>

### Deploy K8s:

1. Run the Command.

   - `nano ~/.aws/credentials`
   - Update file with your keys generated at IAM
   - `[default]`
   - `aws_access_key_id = 12345`
   - `aws_secret_access_key = 12345`

2. Create s3 bucket for state management and update the bucket in the version.tf file.

   - `aws s3api create-bucket --bucket meou-eks --region us-east-1`

3. Create Dynamo Table for lock management and update the dynamodb_table in the version.tf file.

   - `aws dynamodb create-table --table-name MeouCollection --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1`

4. Create testing.tfvars and add the ff.

   - `region = us-east-2`
   - `vpc_name = eks_vpc`
   - `vpc_cidr = 10.2.0.0/16`
   - `eks_cluster_name = eks_cluster`
   - `cidr_block_igw = 0.0.0.0/0`
   - `node_group_name = eks_ng`
   - `ng_instance_types = [ "t2.micro" ]`
   - `disk_size = 10`
   - `desired_nodes = 3`
   - `max_nodes = 4`
   - `min_nodes = 1`
   - `fargate_profile_name=eks_fargate`
   - `kubernetes_namespace = meou-system`

5. Run Terraform Commands.

   - `cd meou-eks `
   - `terraform init`
   - `terraform workspace new testing`
   - `terraform workspace select testing`
   - `terraform apply -var-file=testing.tfvars`

6. Update Kubectl Config.

   - `aws eks --region us-east-2 update-kubeconfig --name eks_cluster-testing`
