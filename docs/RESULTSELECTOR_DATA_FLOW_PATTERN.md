# ResultSelector Data Flow Pattern for ECS Tasks in Step Functions

## Overview

This document describes the **ResultSelector pattern** used in the ECS Zarr conversion migration
to solve the critical problem of passing data between ECS tasks in AWS Step Functions.

## The Problem

When using ECS tasks in Step Functions, there's a fundamental challenge:

**ECS tasks don't return structured output to Step Functions like Lambda functions do.**

### Why This Is a Problem

In a typical data pipeline, each step needs to pass information to the next step:

```
Step 1: Convert file.nc → file.zarr
  ↓ (needs to pass: zarr_key = "zarr/file.zarr")
Step 2: Generate COG from file.zarr → file.tif
  ↓ (needs to pass: cog_key = "cog/file.tif")
Step 3: Create STAC metadata with both keys
```

**With Lambda**: Lambda returns a JSON object that Step Functions can use:
```json
{
  "zarr_key": "zarr/file.zarr",
  "zarr_bucket": "my-bucket"
}
```

**With ECS**: ECS tasks don't return anything to Step Functions. The task just succeeds or fails.

### Failed Approaches

1. **Writing results to S3**: 
   - Problem: Step Functions can't read S3 files directly
   - Would need another Lambda just to read the result file
   - Adds complexity, cost, and potential timing issues

2. **Using task output**:
   - Problem: ECS task output is not accessible to Step Functions
   - Only works with Lambda, not ECS

3. **Environment variables in task**:
   - Problem: Can't read environment variables from a completed task
   - No API to retrieve this information


## The Solution: ResultSelector Pattern

The breakthrough insight is: **We can compute the output deterministically from the input.**

### Key Insight

If we know:
1. The input filename: `ingestion/file.nc`
2. The transformation rule: Replace `ingestion/` with `zarr/` and `.nc` with `.zarr`

Then we can compute the output: `zarr/file.zarr`

**And Step Functions has full visibility into the input we passed to the ECS task!**

### How It Works

Step Functions' `ResultSelector` feature allows us to transform the task result before passing
it to the next state. We use this to extract the input parameters from the task configuration
and compute the output.

#### Step 1: Pass Input to ECS Task

```json
{
  "Type": "Task",
  "Resource": "arn:aws:states:::ecs:runTask.sync",
  "Parameters": {
    "Overrides": {
      "ContainerOverrides": [{
        "Name": "zarr-converter",
        "Environment": [
          { "Name": "INPUT_BUCKET", "Value.$": "$.bucket" },
          { "Name": "INPUT_KEY", "Value.$": "$.key" },
          { "Name": "OUTPUT_BUCKET", "Value": "my-zarr-bucket" }
        ]
      }]
    }
  }
}
```

#### Step 2: Extract and Transform with ResultSelector

```json
{
  "ResultSelector": {
    "zarr_key.$": "States.Format('zarr/{}', 
      States.StringReplace(
        States.ArrayGetItem(
          States.StringSplit(
            $.Overrides.ContainerOverrides[0].Environment[?(@.Name == 'INPUT_KEY')].Value,
            '/'
          ),
          1
        ),
        '.nc',
        '.zarr'
      )
    )",
    "zarr_bucket": "my-zarr-bucket",
    "status": "success"
  },
  "ResultPath": "$.zarr_conversion"
}
```

#### Step 3: Use Output in Next State

```json
{
  "Type": "Task",
  "Resource": "arn:aws:states:::ecs:runTask.sync",
  "Parameters": {
    "Overrides": {
      "ContainerOverrides": [{
        "Name": "cog-generator",
        "Environment": [
          { "Name": "ZARR_BUCKET", "Value.$": "$.zarr_conversion.zarr_bucket" },
          { "Name": "ZARR_KEY", "Value.$": "$.zarr_conversion.zarr_key" },
          { "Name": "OUTPUT_BUCKET", "Value": "my-cog-bucket" }
        ]
      }]
    }
  }
}
```

### Breaking Down the JSONPath Expression

Let's break down the complex JSONPath expression step by step:

**Input**: `$.Overrides.ContainerOverrides[0].Environment[?(@.Name == 'INPUT_KEY')].Value`
- Value: `"ingestion/file.nc"`

**Step 1**: `States.StringSplit(..., '/')`
- Splits by `/`
- Result: `["ingestion", "file.nc"]`

**Step 2**: `States.ArrayGetItem(..., 1)`
- Gets second element (index 1)
- Result: `"file.nc"`

**Step 3**: `States.StringReplace(..., '.nc', '.zarr')`
- Replaces `.nc` with `.zarr`
- Result: `"file.zarr"`

**Step 4**: `States.Format('zarr/{}', ...)`
- Prepends `zarr/`
- Result: `"zarr/file.zarr"`


## Complete Example

### State Machine Definition

```json
{
  "StartAt": "ConvertToZarr",
  "States": {
    "ConvertToZarr": {
      "Type": "Task",
      "Resource": "arn:aws:states:::ecs:runTask.sync",
      "Parameters": {
        "LaunchType": "FARGATE",
        "Cluster": "my-cluster",
        "TaskDefinition": "zarr-conversion",
        "NetworkConfiguration": {
          "AwsvpcConfiguration": {
            "Subnets": ["subnet-123"],
            "SecurityGroups": ["sg-456"]
          }
        },
        "Overrides": {
          "ContainerOverrides": [{
            "Name": "zarr-converter",
            "Environment": [
              { "Name": "INPUT_BUCKET", "Value.$": "$.bucket" },
              { "Name": "INPUT_KEY", "Value.$": "$.key" },
              { "Name": "OUTPUT_BUCKET", "Value": "my-zarr-bucket" }
            ]
          }]
        }
      },
      "ResultSelector": {
        "zarr_key.$": "States.Format('zarr/{}', States.StringReplace(States.ArrayGetItem(States.StringSplit($.Overrides.ContainerOverrides[0].Environment[?(@.Name == 'INPUT_KEY')].Value, '/'), 1), '.nc', '.zarr'))",
        "zarr_bucket": "my-zarr-bucket",
        "status": "success"
      },
      "ResultPath": "$.zarr_conversion",
      "Next": "GenerateCOG"
    },
    "GenerateCOG": {
      "Type": "Task",
      "Resource": "arn:aws:states:::ecs:runTask.sync",
      "Parameters": {
        "LaunchType": "FARGATE",
        "Cluster": "my-cluster",
        "TaskDefinition": "cog-generation",
        "NetworkConfiguration": {
          "AwsvpcConfiguration": {
            "Subnets": ["subnet-123"],
            "SecurityGroups": ["sg-456"]
          }
        },
        "Overrides": {
          "ContainerOverrides": [{
            "Name": "cog-generator",
            "Environment": [
              { "Name": "ZARR_BUCKET", "Value.$": "$.zarr_conversion.zarr_bucket" },
              { "Name": "ZARR_KEY", "Value.$": "$.zarr_conversion.zarr_key" },
              { "Name": "OUTPUT_BUCKET", "Value": "my-cog-bucket" }
            ]
          }]
        }
      },
      "ResultSelector": {
        "cog_key.$": "States.Format('cog/{}.tif', States.StringReplace(States.ArrayGetItem(States.StringSplit($.Overrides.ContainerOverrides[0].Environment[?(@.Name == 'ZARR_KEY')].Value, '/'), 1), '.zarr', ''))",
        "cog_bucket": "my-cog-bucket",
        "status": "success"
      },
      "ResultPath": "$.cog_generation",
      "Next": "CreateSTAC"
    },
    "CreateSTAC": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "stac-creator",
        "Payload": {
          "zarr_bucket.$": "$.zarr_conversion.zarr_bucket",
          "zarr_key.$": "$.zarr_conversion.zarr_key",
          "cog_bucket.$": "$.cog_generation.cog_bucket",
          "cog_key.$": "$.cog_generation.cog_key"
        }
      },
      "End": true
    }
  }
}
```

### Data Flow Through States

**Initial Input**:
```json
{
  "bucket": "my-raw-bucket",
  "key": "ingestion/A2002070120230731_MC_SST_std_coastal_v05.nc"
}
```

**After ConvertToZarr**:
```json
{
  "bucket": "my-raw-bucket",
  "key": "ingestion/A2002070120230731_MC_SST_std_coastal_v05.nc",
  "zarr_conversion": {
    "zarr_key": "zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr",
    "zarr_bucket": "my-zarr-bucket",
    "status": "success"
  }
}
```

**After GenerateCOG**:
```json
{
  "bucket": "my-raw-bucket",
  "key": "ingestion/A2002070120230731_MC_SST_std_coastal_v05.nc",
  "zarr_conversion": {
    "zarr_key": "zarr/A2002070120230731_MC_SST_std_coastal_v05.zarr",
    "zarr_bucket": "my-zarr-bucket",
    "status": "success"
  },
  "cog_generation": {
    "cog_key": "cog/A2002070120230731_MC_SST_std_coastal_v05.tif",
    "cog_bucket": "my-cog-bucket",
    "status": "success"
  }
}
```


## Advantages of This Pattern

### 1. No Additional Infrastructure
- ✅ No S3 reads/writes for result passing
- ✅ No additional Lambda functions needed
- ✅ No timing issues or race conditions

### 2. Zero Latency
- ✅ Transformation happens instantly in Step Functions
- ✅ No network calls required
- ✅ No waiting for S3 writes/reads

### 3. 100% Reliable
- ✅ Deterministic transformation
- ✅ No external dependencies
- ✅ Works with Step Functions' native features

### 4. Cost Effective
- ✅ No additional Lambda invocations
- ✅ No S3 API calls for result passing
- ✅ No data transfer costs

### 5. Easy to Debug
- ✅ All data visible in Step Functions execution history
- ✅ No hidden state in S3
- ✅ Clear data flow through states

## Limitations and Considerations

### When This Pattern Works

✅ **Output can be computed from input**
- Filename transformations
- Predictable key patterns
- Deterministic operations

✅ **Transformation rules are simple**
- String replacement
- Path manipulation
- Format conversion

### When This Pattern Doesn't Work

❌ **Output depends on file content**
- Bounding boxes (need to read NetCDF)
- File sizes
- Checksums
- Metadata extraction

❌ **Non-deterministic outputs**
- Generated UUIDs
- Timestamps
- Random values

### Workarounds for Complex Data

For data that can't be computed (like bounding boxes), use a **metadata file pattern**:

1. **ECS task writes metadata to S3**:
   ```python
   metadata = {
       "bbox": extract_bounding_box(dataset),
       "zarr_key": output_key,
       "zarr_bucket": output_bucket
   }
   s3.put_object(
       Bucket=output_bucket,
       Key=f"{output_key}_metadata.json",
       Body=json.dumps(metadata)
   )
   ```

2. **Lambda reads metadata from S3**:
   ```python
   metadata_key = f"{zarr_key}_metadata.json"
   metadata = json.loads(s3.get_object(
       Bucket=zarr_bucket,
       Key=metadata_key
   )['Body'].read())
   bbox = metadata['bbox']
   ```

This combines the best of both approaches:
- Simple data (keys) uses ResultSelector
- Complex data (bounding boxes) uses S3 metadata files

## Step Functions JSONPath Reference

### Available Functions

**String Operations**:
- `States.Format(template, ...args)` - Format string with placeholders
- `States.StringSplit(string, delimiter)` - Split string into array
- `States.StringReplace(string, old, new)` - Replace substring

**Array Operations**:
- `States.ArrayGetItem(array, index)` - Get array element by index
- `States.ArrayLength(array)` - Get array length

**JSON Operations**:
- `States.JsonToString(json)` - Convert JSON to string
- `States.StringToJson(string)` - Parse JSON string

**JSONPath Filters**:
- `$.array[?(@.key == 'value')]` - Filter array by condition
- `$.array[*].key` - Get all values of key from array

### Common Patterns

**Extract filename from path**:
```json
"filename.$": "States.ArrayGetItem(States.StringSplit($.key, '/'), -1)"
```

**Remove file extension**:
```json
"basename.$": "States.ArrayGetItem(States.StringSplit($.filename, '.'), 0)"
```

**Change file extension**:
```json
"new_filename.$": "States.Format('{}.{}', $.basename, 'zarr')"
```

**Replace path prefix**:
```json
"new_path.$": "States.Format('output/{}', States.ArrayGetItem(States.StringSplit($.key, '/'), 1))"
```


## Testing the Pattern

### Unit Testing Transformations

Test the transformation logic separately:

```python
def test_filename_transformation():
    """Test NetCDF to Zarr filename transformation"""
    assert transform_key("ingestion/file.nc") == "zarr/file.zarr"
    assert transform_key("ingestion/subdir/file.nc") == "zarr/subdir/file.zarr"
    assert transform_key("ingestion/file-2023.nc") == "zarr/file-2023.zarr"

def test_zarr_to_cog_transformation():
    """Test Zarr to COG filename transformation"""
    assert transform_key("zarr/file.zarr") == "cog/file.tif"
    assert transform_key("zarr/subdir/file.zarr") == "cog/subdir/file.tif"
```

### Integration Testing

Test the complete Step Functions execution:

```python
def test_data_flow_through_states():
    """Test data flows correctly through Step Functions states"""
    # Start execution
    response = sfn.start_execution(
        stateMachineArn=state_machine_arn,
        input=json.dumps({
            "bucket": "test-bucket",
            "key": "ingestion/test.nc"
        })
    )
    
    # Wait for completion
    execution_arn = response['executionArn']
    wait_for_execution(execution_arn)
    
    # Get execution history
    history = sfn.get_execution_history(executionArn=execution_arn)
    
    # Verify data flow
    zarr_state_output = get_state_output(history, "ConvertToZarr")
    assert zarr_state_output['zarr_conversion']['zarr_key'] == "zarr/test.zarr"
    
    cog_state_output = get_state_output(history, "GenerateCOG")
    assert cog_state_output['cog_generation']['cog_key'] == "cog/test.tif"
```

### Property-Based Testing

Test with random inputs to ensure transformations always work:

```python
from hypothesis import given, strategies as st

@given(st.text(min_size=1, alphabet=st.characters(blacklist_characters="/")))
def test_transformation_always_valid(filename):
    """For any filename, transformation should produce valid output"""
    input_key = f"ingestion/{filename}.nc"
    output_key = transform_to_zarr(input_key)
    
    # Verify output format
    assert output_key.startswith("zarr/")
    assert output_key.endswith(".zarr")
    
    # Verify reversibility (for debugging)
    basename = extract_basename(output_key)
    assert basename == filename
```

## Troubleshooting

### Issue: JSONPath Expression Fails

**Symptoms**:
- Step Functions execution fails with JSONPath error
- Error message: "The JSONPath ... is invalid"

**Solutions**:
1. Test JSONPath in Step Functions simulator
2. Verify input data structure matches expected format
3. Check for special characters in filenames

### Issue: Wrong Output Key Generated

**Symptoms**:
- Output key doesn't match expected pattern
- Next state receives incorrect input

**Solutions**:
1. Check transformation logic in ResultSelector
2. Verify input key format
3. Test with Step Functions execution history

### Issue: Data Not Passed to Next State

**Symptoms**:
- Next state doesn't receive expected data
- Error: "The value for the field ... must be a STRING"

**Solutions**:
1. Verify `ResultPath` is set correctly
2. Check JSONPath references in next state
3. Ensure data structure matches expectations

## Best Practices

### 1. Use Consistent Naming Patterns

✅ **Good**: Predictable patterns
```
ingestion/file.nc → zarr/file.zarr → cog/file.tif → stac/file.json
```

❌ **Bad**: Inconsistent patterns
```
input/file.nc → zarr-output/file_converted.zarr → cog_files/file.tiff
```

### 2. Document Transformation Rules

Always document the transformation logic:

```json
{
  "Comment": "Transform ingestion/*.nc to zarr/*.zarr",
  "ResultSelector": {
    "zarr_key.$": "..."
  }
}
```

### 3. Test Edge Cases

Test with:
- Long filenames
- Special characters
- Subdirectories
- Multiple dots in filename

### 4. Keep Transformations Simple

If transformation becomes too complex, consider:
- Simplifying naming conventions
- Using Lambda for complex logic
- Breaking into multiple steps

### 5. Validate Inputs

Add validation at the start of the state machine:

```json
{
  "Type": "Choice",
  "Choices": [{
    "Variable": "$.key",
    "StringMatches": "ingestion/*.nc",
    "Next": "ConvertToZarr"
  }],
  "Default": "InvalidInput"
}
```

## Conclusion

The ResultSelector pattern is a powerful technique for passing data between ECS tasks in
Step Functions without additional infrastructure. It works by:

1. Computing output deterministically from input
2. Using Step Functions' native JSONPath transformation
3. Storing results in state output for next steps

This pattern is:
- ✅ Simple and elegant
- ✅ Cost-effective (no additional resources)
- ✅ Reliable (deterministic)
- ✅ Fast (zero latency)
- ✅ Easy to debug (all data visible)

Use this pattern whenever:
- Output can be computed from input
- Transformation rules are simple
- You want to avoid additional infrastructure

For complex data that can't be computed, combine with the metadata file pattern.

## References

- [AWS Step Functions JSONPath Documentation](https://docs.aws.amazon.com/step-functions/latest/dg/amazon-states-language-paths.html)
- [ResultSelector Documentation](https://docs.aws.amazon.com/step-functions/latest/dg/input-output-resultselector.html)
- [ECS Integration Documentation](https://docs.aws.amazon.com/step-functions/latest/dg/connect-ecs.html)
- [Design Document](../.kiro/specs/ecs-zarr-conversion-migration/design.md)

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Author**: Platform Team

