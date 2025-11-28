FROM public.ecr.aws/lambda/python:3.12

WORKDIR ${LAMBDA_TASK_ROOT}

# Install uv for faster pip installs
RUN pip install uv

COPY requirements.txt .
RUN uv pip install --system -r requirements.txt

COPY zarr_converter_lambda.py .
CMD ["zarr_converter_lambda.lambda_handler"]
