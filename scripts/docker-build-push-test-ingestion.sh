cd app
docker build -t 123456789101.dkr.ecr.ap-southeast-2.amazonaws.com/cloud-scientific-raster-sharing-repo:latest . && docker push 123456789101.dkr.ecr.ap-southeast-2.amazonaws.com/cloud-scientific-raster-sharing-repo:latest

cd ../terraform
terraform taint module.ecs.aws_ecs_task_definition.cog_generation
terraform apply -auto-approve

cd ..
./debug_ingestion.sh
