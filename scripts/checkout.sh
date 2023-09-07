#!/bin/bash
USER="$(whoami)"
SLACK_URL="$SLACK_URL"
CLUSTER="$ECS_CLUSTER"
SERVICE_NAME="$1"
SERVICE="$SERVICE_NAME-management"

# create a function to validate the SLACK_URL has https:// in it. If not, add it.
function validate_slack_url() {
    if [[ $SLACK_URL == https://* ]]; then
        echo "Valid Slack URL"
    else
        echo "Invalid Slack URL, adding https://"
        SLACK_URL="https://$SLACK_URL"
    fi
}

echo "-> Validating Service Name"
  if ! [[ "$1" == "ServiceName1" ||  "$1" == "ServiceName2" ]];  then
      echo "-> $1 is not a valid service, please choose a valid service name"; exit
  fi;

echo '-> Cleaning up any old sessions that might have been left behind'
PREPLIST=$(aws ecs list-tasks --region $AWS_REGION --cluster $CLUSTER --started-by user-console/$USER)
KILLTASK=$(echo $PREPLIST | jq -r '.taskArns[0]')
  if [ "$KILLTASK" == "null" ]; then
      echo "-> No task to kill";
  else
      echo "-> Stopping the old Task: ||"$KILLTASK"||"
        STOPTASK=$(aws ecs stop-task --region $AWS_REGION \
          --cluster $CLUSTER \
          --task $KILLTASK)
  fi;

echo '-> Starting task...'
STARTTASK=$(aws ecs run-task --region $AWS_REGION --cluster $CLUSTER --task-definition $SERVICE --started-by user-console/$USER)
TASK_ID=$(aws ecs list-tasks --region $AWS_REGION --cluster $CLUSTER --started-by user-console/$USER | jq -r '.taskArns[0]' )
TASKSTATUS(){
    CHECKSTATUS=$(aws ecs describe-tasks --region $AWS_REGION --cluster=$CLUSTER --tasks $TASK_ID | jq -r '.tasks[0].containers[0].lastStatus')
    }

echo "-> Waiting for Task to become Available"
while [ "$CHECKSTATUS" == 'PENDING' ] || [ -z "$CHECKSTATUS" ]; do
    TASKSTATUS
    if [ "$CHECKSTATUS" == 'PENDING' ]; then
        echo -n "#"
        sleep .1
    fi;
done
echo ""
echo "-> Task Status: $CHECKSTATUS"

echo '-> Gathering Facts'
CONTAINER_INSTANCE_ID=$(aws ecs describe-tasks --region $AWS_REGION --cluster=$CLUSTER --tasks $TASK_ID | jq -r '.tasks[0].containerInstanceArn' )
EC2_INSTANCE_ID=$(aws ecs describe-container-instances --region $AWS_REGION  --cluster=$CLUSTER --container-instances $CONTAINER_INSTANCE_ID | jq -r '.containerInstances[0].ec2InstanceId' )
  if [ "$EC2_INSTANCE_ID" == null ]; then
      echo "-> No Instance Id found"; exit 3
  else
      echo "-> Instance ID Found -> $EC2_INSTANCE_ID"
  fi;
EC2_INSTANCE_IP=$(aws ec2 describe-instances --region $AWS_REGION --instance-ids $EC2_INSTANCE_ID | jq -r '.Reservations[].Instances[].NetworkInterfaces[].PrivateIpAddresses[].PrivateIpAddress')

echo '-> Logging into your console'
data1="$USER has started a console session"
payload1='payload={"channel": "#slack_channel", "username": "Console", "attachments":[
        {
            "fallback": "Required plain-text summary of the attachment.",
            "color": "#3AA3E3",
            "pretext": "'"${data1}"'",
            "fields": [
                {
                    "title": "Cluster",
                    "value": "'"${CLUSTER}"'",
                    "short": true
                },
                       {
                    "title": "Application",
                    "value": "'"${SERVICE}"'",
                    "short": true
                }
            ]
        }
    ]}'

curl \
    -H "Accept: application/json" \
    -X POST \
    --data-urlencode "${payload1}" \
    $SLACK_URL

ssh -i ~/.ssh/$PEM ec2-user@$EC2_INSTANCE_IP -t 'bash -c "docker exec -it $( docker ps -a -q -f name='$SERVICE' | head -n 1 ) /bin/bash"'

echo '-> Stopping task...'
STOPTASK=$(aws ecs stop-task --region $AWS_REGION --cluster $CLUSTER --task $TASK_ID --reason 'user-console/stop')
echo -e '\r-> Stopping task... done'
data2="$USER has ended the rails console session"
payload2='payload={"channel": "#slach_channel", "username": "Console", "attachments":[
        {
            "fallback": "Required plain-text summary of the attachment.",
            "color": "good",
            "pretext": "'"${data2}"'",
            "fields": [
                {
                    "title": "Cluster",
                    "value": "'"${CLUSTER}"'",
                    "short": true
                },
                       {
                    "title": "Application",
                    "value": "'"${SERVICE}"'",
                    "short": true
                }
            ]
        }
    ]}'

curl \
    -H "Accept: application/json" \
    -X POST \
    --data-urlencode "${payload2}" \
    $SLACK_URL
