pipeline {
  agent { label 'terraform-linux' }

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
    skipDefaultCheckout(true)
  }

  parameters {
    choice(name: 'ACTION', choices: ['PLAN', 'APPLY'], description: 'PLAN never applies infrastructure.')
    choice(name: 'ENVIRONMENT', choices: ['dev', 'integration', 'pre', 'prod'], description: 'Isolated Terraform environment.')
    string(name: 'AWS_REGION', defaultValue: 'us-east-1', trim: true, description: 'AWS region for this deployment.')
    booleanParam(name: 'AUTO_APPROVE', defaultValue: false, description: 'Does not bypass any Jenkins approval gate; production rejects true.')
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          def sourceBranch = env.CHANGE_BRANCH ?: env.BRANCH_NAME ?: 'unknown'
          def pullRequest = env.CHANGE_ID ?: 'none'
          currentBuild.description = "${params.ACTION} ${params.ENVIRONMENT} | PR ${pullRequest}"
          echo "PR: ${pullRequest}; source branch: ${sourceBranch}; target: ${env.CHANGE_TARGET ?: 'n/a'}"

          if (params.AUTO_APPROVE && params.ENVIRONMENT == 'prod') {
            error('AUTO_APPROVE=true is not permitted for production.')
          }
          if (params.ACTION == 'APPLY' && !env.CHANGE_ID) {
            error('APPLY is only permitted for a GitHub pull request build.')
          }
        }
      }
    }

    stage('Validate') {
      steps {
        script {
          withTerraformRole(params.ENVIRONMENT) {
            withCredentials([string(credentialsId: 'terraform-state-bucket', variable: 'TF_STATE_BUCKET')]) {
              dir("environments/${params.ENVIRONMENT}") {
                sh '''
                  set +x
                  terraform fmt -check -recursive ../..
                  terraform init -input=false \
                    -backend-config=backend.hcl \
                    -backend-config="bucket=$TF_STATE_BUCKET" \
                    -backend-config="region=$AWS_REGION"
                  terraform validate
                '''
              }
            }
          }
        }
      }
    }

    stage('Security Scan') {
      steps {
        sh '''
          set +x
          if command -v checkov >/dev/null 2>&1; then
            checkov --directory . --framework terraform --quiet
          elif command -v tfsec >/dev/null 2>&1; then
            tfsec .
          else
            echo "Install Checkov or tfsec on the Jenkins agent."
            exit 1
          fi
        '''
      }
    }

    stage('Terraform Delivery') {
      options {
        lock(resource: "terraform-${params.ENVIRONMENT}")
      }
      stages {
        stage('Terraform Plan') {
          steps {
            script {
              withTerraformRole(params.ENVIRONMENT) {
                withCredentials([string(credentialsId: 'terraform-state-bucket', variable: 'TF_STATE_BUCKET')]) {
                  dir("environments/${params.ENVIRONMENT}") {
                    sh '''
                      set +x
                      plan_status=0
                      terraform plan -input=false -detailed-exitcode \
                        -var-file=terraform.tfvars \
                        -var="aws_region=$AWS_REGION" \
                        -out=tfplan || plan_status=$?
                      if [ "$plan_status" -gt 2 ]; then
                        exit "$plan_status"
                      fi
                      terraform show -no-color tfplan > tfplan.txt
                    '''
                    archiveArtifacts artifacts: "environments/${params.ENVIRONMENT}/tfplan,environments/${params.ENVIRONMENT}/tfplan.txt", fingerprint: true
                  }
                }
              }
            }
          }
        }

        stage('Approval') {
          when {
            expression { params.ACTION == 'APPLY' }
          }
          steps {
            script {
              if (!env.CHANGE_ID) {
                error('An open GitHub pull request is required before APPLY.')
              }
              withCredentials([string(credentialsId: 'github-pr-read-token', variable: 'GH_TOKEN')]) {
                dir("environments/${params.ENVIRONMENT}") {
                  sh '''
                    set +x
                    approval=$(gh pr view "$CHANGE_ID" --json state,reviewDecision \
                      --jq 'select(.state == "OPEN" and .reviewDecision == "APPROVED")')
                    if [ -z "$approval" ]; then
                      echo "The pull request must be open and have an approved GitHub review before APPLY."
                      exit 1
                    fi
                  '''
                }
              }
              if (params.AUTO_APPROVE) {
                echo 'AUTO_APPROVE is ignored for non-production: the Jenkins approval below is still mandatory.'
              }
              timeout(time: 2, unit: 'HOURS') {
                input(
                  message: "Approve the saved ${params.ENVIRONMENT} plan for PR #${env.CHANGE_ID}?",
                  ok: 'Approve reviewed plan',
                  submitter: 'terraform-approvers',
                  submitterParameter: 'APPROVED_BY'
                )
              }
            }
          }
        }

        stage('Terraform Apply') {
          when {
            expression { params.ACTION == 'APPLY' }
          }
          steps {
            script {
              withTerraformRole(params.ENVIRONMENT) {
                withCredentials([string(credentialsId: 'terraform-state-bucket', variable: 'TF_STATE_BUCKET')]) {
                  dir("environments/${params.ENVIRONMENT}") {
                    sh '''
                      set +x
                      test -s tfplan
                      terraform apply -input=false tfplan
                      terraform output -json > terraform-outputs.json
                    '''
                    archiveArtifacts artifacts: "environments/${params.ENVIRONMENT}/terraform-outputs.json", fingerprint: true
                  }
                }
              }
            }
          }
        }

        stage('Verify') {
          when {
            expression { params.ACTION == 'APPLY' }
          }
          steps {
            script {
              withTerraformRole(params.ENVIRONMENT) {
                withCredentials([string(credentialsId: 'terraform-state-bucket', variable: 'TF_STATE_BUCKET')]) {
                  dir("environments/${params.ENVIRONMENT}") {
                    sh '''
                      set +x
                      terraform output -json > terraform-outputs.json
                      vpc_id=$(jq -r '.vpc_id.value' terraform-outputs.json)
                      subnet_id=$(jq -r '.subnet_id.value' terraform-outputs.json)
                      instance_ids=$(jq -r '.instance_ids.value | join(" ")' terraform-outputs.json)

                      aws ec2 describe-vpcs --vpc-ids "$vpc_id" \
                        --query 'Vpcs[0].VpcId' --output text | grep -Fx "$vpc_id"
                      aws ec2 describe-subnets --subnet-ids "$subnet_id" \
                        --query 'Subnets[0].SubnetId' --output text | grep -Fx "$subnet_id"

                      instance_count=$(aws ec2 describe-instances --instance-ids $instance_ids \
                        --query 'length(Reservations[].Instances[])' --output text)
                      test "$instance_count" -eq 2

                      jq -r '.bucket_names.value[]' terraform-outputs.json | while IFS= read -r bucket; do
                        aws s3api head-bucket --bucket "$bucket"
                      done
                    '''
                    archiveArtifacts artifacts: "environments/${params.ENVIRONMENT}/terraform-outputs.json", fingerprint: true
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  post {
    success {
      echo 'Terraform pipeline completed successfully. Jenkins SCM integration publishes the build status to GitHub.'
    }
    failure {
      echo 'Terraform pipeline failed. Review the stage logs and archived plan output; no automatic merge was attempted.'
    }
    always {
      cleanWs()
    }
  }
}

def withTerraformRole(String targetEnvironment, Closure body) {
  def roleName = env["TF_ROLE_${targetEnvironment.toUpperCase()}"]
  if (!env.AWS_ACCOUNT_ID || !roleName) {
    error("Configure AWS_ACCOUNT_ID and TF_ROLE_${targetEnvironment.toUpperCase()} in Jenkins.")
  }

  withAWS(
    role: roleName,
    roleAccount: env.AWS_ACCOUNT_ID,
    region: params.AWS_REGION,
    roleSessionName: "terraform-${targetEnvironment}-${env.BUILD_NUMBER}",
    useNode: true,
    duration: 3600
  ) {
    body()
  }
}
