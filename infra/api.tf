# Existing REST API + Lambdas, adopted as-is so the current code deploys from this repo.
# These are replaced by the DynamoDB-backed rewrite later. The legacy REST API
# (photos-ryantate314) and its Lambda (photos-ryantate314) are NOT managed here; they are
# unused by CloudFront and will be deleted.

# --- Lambda execution role (console-generated; shared by all photo Lambdas) -------

resource "aws_iam_role" "lambda" {
  name = "photos-ryantate314-role-do6oauqu"
  path = "/service-role/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_logging" {
  name = "AWSLambdaBasicExecutionRole-6bfb611e-ae1e-4961-939b-c4acf8180adb"
  path = "/service-role/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "arn:${data.aws_partition.current.partition}:logs:${var.region}:${local.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["arn:${data.aws_partition.current.partition}:logs:${var.region}:${local.account_id}:log-group:*"]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

# --- Lambda functions --------------------------------------------------------------
# The code in ../api is ESM; the runtime needs it as index.mjs.

data "archive_file" "album" {
  type        = "zip"
  output_path = "${path.module}/.build/album.zip"
  source {
    content  = file("${path.module}/../api/album.js")
    filename = "index.mjs"
  }
}

data "archive_file" "album_all" {
  type        = "zip"
  output_path = "${path.module}/.build/album-all.zip"
  source {
    content  = file("${path.module}/../api/album-all.js")
    filename = "index.mjs"
  }
}

resource "aws_lambda_function" "album" {
  function_name    = "photos-ryantate314-api-album"
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  architectures    = ["x86_64"]
  memory_size      = 128
  timeout          = 3
  filename         = data.archive_file.album.output_path
  source_code_hash = data.archive_file.album.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.album]
}

resource "aws_lambda_function" "album_all" {
  function_name    = "photos-ryantate314-net-api-album-all"
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  architectures    = ["x86_64"]
  memory_size      = 128
  timeout          = 370
  filename         = data.archive_file.album_all.output_path
  source_code_hash = data.archive_file.album_all.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.album_all]
}

resource "aws_cloudwatch_log_group" "album" {
  name              = "/aws/lambda/photos-ryantate314-api-album"
  retention_in_days = 14
}

# Live group has no retention (never expires); 14 days matches the sibling group.
resource "aws_cloudwatch_log_group" "album_all" {
  name              = "/aws/lambda/photos-ryantate314-net-api-album-all"
  retention_in_days = 14
}

# --- REST API "photos-ryantate314-net", stage "api" --------------------------------

resource "aws_api_gateway_rest_api" "photos" {
  name = "photos-ryantate314-net"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "shoots" {
  rest_api_id = aws_api_gateway_rest_api.photos.id
  parent_id   = aws_api_gateway_rest_api.photos.root_resource_id
  path_part   = "shoots"
}

resource "aws_api_gateway_resource" "shoot" {
  rest_api_id = aws_api_gateway_rest_api.photos.id
  parent_id   = aws_api_gateway_resource.shoots.id
  path_part   = "{shootId}"
}

resource "aws_api_gateway_resource" "albums" {
  rest_api_id = aws_api_gateway_rest_api.photos.id
  parent_id   = aws_api_gateway_resource.shoot.id
  path_part   = "albums"
}

resource "aws_api_gateway_resource" "album" {
  rest_api_id = aws_api_gateway_rest_api.photos.id
  parent_id   = aws_api_gateway_resource.albums.id
  path_part   = "{albumId}"
}

resource "aws_api_gateway_method" "albums_get" {
  rest_api_id   = aws_api_gateway_rest_api.photos.id
  resource_id   = aws_api_gateway_resource.albums.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.shootId" = true
  }
}

resource "aws_api_gateway_method" "album_get" {
  rest_api_id   = aws_api_gateway_rest_api.photos.id
  resource_id   = aws_api_gateway_resource.album.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.shootId" = true
    "method.request.path.albumId" = true
  }
}

resource "aws_api_gateway_integration" "albums_get" {
  rest_api_id             = aws_api_gateway_rest_api.photos.id
  resource_id             = aws_api_gateway_resource.albums.id
  http_method             = aws_api_gateway_method.albums_get.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.album_all.invoke_arn
  content_handling        = "CONVERT_TO_TEXT"
}

resource "aws_api_gateway_integration" "album_get" {
  rest_api_id             = aws_api_gateway_rest_api.photos.id
  resource_id             = aws_api_gateway_resource.album.id
  http_method             = aws_api_gateway_method.album_get.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.album.invoke_arn
  content_handling        = "CONVERT_TO_TEXT"
}

# The deployment is adopted as-is. It has no redeploy trigger yet: after changing methods or
# integrations, add `triggers` (with create_before_destroy) in a reviewed change.
resource "aws_api_gateway_deployment" "photos" {
  rest_api_id = aws_api_gateway_rest_api.photos.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api" {
  rest_api_id   = aws_api_gateway_rest_api.photos.id
  deployment_id = aws_api_gateway_deployment.photos.id
  stage_name    = "api"
}

resource "aws_lambda_permission" "albums_apigw" {
  statement_id  = "90da22fd-b7d2-50f3-bb30-e047bd6b5203"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.album_all.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.photos.execution_arn}/*/GET/shoots/*/albums"
}

resource "aws_lambda_permission" "album_apigw" {
  statement_id  = "8d336918-62eb-5cd3-88fb-f05d8239981e"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.album.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.photos.execution_arn}/*/GET/shoots/*/albums/*"
}
