provider "aws" {
  region = "eu-north-1"
}

# Создание VPC (одной для всех ресурсов)
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Subnet в зоне доступности eu-north-1a
resource "aws_subnet" "main_subnet_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-north-1a"
}

# Subnet в зоне доступности eu-north-1b
resource "aws_subnet" "main_subnet_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-north-1b"
}

# Subnet Group для Aurora
resource "aws_db_subnet_group" "main" {
  name        = "aurora_subnet_group"
  subnet_ids  = [aws_subnet.main_subnet_1a.id, aws_subnet.main_subnet_1b.id]
  description = "Subnet group for Aurora"
}

# Security Group в той же VPC для всех ресурсов
resource "aws_security_group" "rdcp_rds_sg" {
  name        = "aurora_sg"
  description = "Security group for Aurora cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Доступ только из той же VPC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Aurora RDS Cluster
resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier      = "aurora-cluster"
  engine                  = "aurora-postgresql"
  engine_version          = "15.4"
  master_username         = "db_admin"
  master_password         = "password123"
  database_name           = "rdcp_users"
  skip_final_snapshot     = true
  vpc_security_group_ids  = [aws_security_group.rdcp_rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.main.name
}

# Aurora Instance (инстанс r5.large)
resource "aws_rds_cluster_instance" "aurora_instance" {
  count              = 1
  identifier         = "aurora-instance-${count.index}"
  cluster_identifier = aws_rds_cluster.aurora_cluster.id
  instance_class     = "db.r5.large"
  engine             = aws_rds_cluster.aurora_cluster.engine
  publicly_accessible = false
  db_subnet_group_name = aws_db_subnet_group.main.name
}

# Lambda Layer для PostgreSQL (pg)
resource "aws_lambda_layer_version" "pg_layer" {
  filename   = "lambda_zip/lambda_pg_layer.zip"
  layer_name = "pg_layer"
  compatible_runtimes = ["nodejs18.x"]
}

# Lambda для создания таблицы
resource "aws_lambda_function" "rdcp_create_table_lambda" {
  function_name = "rdcp_create_table_lambda"
  role          = aws_iam_role.rdcp_lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  filename      = "lambda_zip/create_table_lambda.zip"
  layers        = [aws_lambda_layer_version.pg_layer.arn]

  source_code_hash = filebase64sha256("lambda_zip/create_table_lambda.zip")

  vpc_config {
    subnet_ids         = [aws_subnet.main_subnet_1a.id, aws_subnet.main_subnet_1b.id]
    security_group_ids = [aws_security_group.rdcp_rds_sg.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_rds_cluster.aurora_cluster.endpoint
      DB_USER     = "db_admin"
      DB_PASSWORD = "password123"
      DB_NAME     = "rdcp_users"
    }
  }
}

# Lambda для POST-запроса
resource "aws_lambda_function" "rdcp_post_lambda" {
  function_name = "rdcp_post_lambda"
  role          = aws_iam_role.rdcp_lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  filename      = "lambda_zip/post_handler.zip"
  layers        = [aws_lambda_layer_version.pg_layer.arn]

  source_code_hash = filebase64sha256("lambda_zip/post_handler.zip")

  vpc_config {
    subnet_ids         = [aws_subnet.main_subnet_1a.id, aws_subnet.main_subnet_1b.id]
    security_group_ids = [aws_security_group.rdcp_rds_sg.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_rds_cluster.aurora_cluster.endpoint
      DB_USER     = "db_admin"
      DB_PASSWORD = "password123"
      DB_NAME     = "rdcp_users"
    }
  }
}

# Lambda для GET-запроса
resource "aws_lambda_function" "rdcp_get_lambda" {
  function_name = "rdcp_get_lambda"
  role          = aws_iam_role.rdcp_lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  filename      = "lambda_zip/get_handler.zip"
  layers        = [aws_lambda_layer_version.pg_layer.arn]

  source_code_hash = filebase64sha256("lambda_zip/get_handler.zip")

  vpc_config {
    subnet_ids         = [aws_subnet.main_subnet_1a.id, aws_subnet.main_subnet_1b.id]
    security_group_ids = [aws_security_group.rdcp_rds_sg.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_rds_cluster.aurora_cluster.endpoint
      DB_USER     = "db_admin"
      DB_PASSWORD = "password123"
      DB_NAME     = "rdcp_users"
    }
  }
}

# Роль и политика для Lambda
resource "aws_iam_role" "rdcp_lambda_role" {
  name = "rdcp_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rdcp_lambda_policy" {
  role       = aws_iam_role.rdcp_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# API Gateway для POST-запроса
resource "aws_api_gateway_rest_api" "rdcp_api_gateway" {
  name = "rdcp_api_gateway"
}

resource "aws_api_gateway_resource" "rdcp_post_resource" {
  rest_api_id = aws_api_gateway_rest_api.rdcp_api_gateway.id
  parent_id   = aws_api_gateway_rest_api.rdcp_api_gateway.root_resource_id
  path_part   = "users"
}

resource "aws_api_gateway_method" "rdcp_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.rdcp_api_gateway.id
  resource_id   = aws_api_gateway_resource.rdcp_post_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "rdcp_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.rdcp_api_gateway.id
  resource_id             = aws_api_gateway_resource.rdcp_post_resource.id
  http_method             = aws_api_gateway_method.rdcp_post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.rdcp_post_lambda.invoke_arn
}

# API Gateway для GET-запроса
resource "aws_api_gateway_method" "rdcp_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.rdcp_api_gateway.id
  resource_id   = aws_api_gateway_resource.rdcp_post_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "rdcp_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.rdcp_api_gateway.id
  resource_id             = aws_api_gateway_resource.rdcp_post_resource.id
  http_method             = aws_api_gateway_method.rdcp_get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.rdcp_get_lambda.invoke_arn
}

# Развертывание API Gateway
resource "aws_api_gateway_deployment" "rdcp_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.rdcp_post_integration,
    aws_api_gateway_integration.rdcp_get_integration,
    aws_iam_policy.cloudwatch_logs_policy
  ]
  rest_api_id = aws_api_gateway_rest_api.rdcp_api_gateway.id
  stage_name  = "prod"
}

# Lambda invocation для создания таблиц в Aurora
resource "aws_lambda_invocation" "invoke_create_table" {
  function_name = aws_lambda_function.rdcp_create_table_lambda.arn
  depends_on = [aws_lambda_function.rdcp_create_table_lambda, aws_rds_cluster_instance.aurora_instance]
  input = jsonencode({
    terraform = true
  })
}

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rdcp_post_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.rdcp_api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_invoke_get" {
  statement_id  = "AllowAPIGatewayInvokeGet"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rdcp_get_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.rdcp_api_gateway.execution_arn}/*/*"
}

# Логирование для CloudWatch

resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "APIGatewayCloudWatchLogsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "cloudwatch_logs_policy" {
  name = "APIGatewayCloudWatchLogsPolicy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_cloudwatch_logs_policy" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = aws_iam_policy.cloudwatch_logs_policy.arn
}

# Указание роли в настройках аккаунта API Gateway
resource "aws_api_gateway_account" "account" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn
}

# CloudWatch log group для API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/api-gateway/rdcp-api-gateway"
  retention_in_days = 14
}

# API Gateway Stage с привязкой к CloudWatch Log Group
resource "aws_api_gateway_stage" "prod_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.rdcp_api_gateway.id
  deployment_id = aws_api_gateway_deployment.rdcp_api_deployment.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format          = jsonencode({
      requestId      = "$context.requestId",
      ip             = "$context.identity.sourceIp",
      caller         = "$context.identity.caller",
      user           = "$context.identity.user",
      requestTime    = "$context.requestTime",
      httpMethod     = "$context.httpMethod",
      resourcePath   = "$context.resourcePath",
      status         = "$context.status",
      protocol       = "$context.protocol",
      responseLength = "$context.responseLength"
    })
  }
}

# Method Settings для включения логирования и метрик
resource "aws_api_gateway_method_settings" "prod_method_settings" {
  rest_api_id = aws_api_gateway_rest_api.rdcp_api_gateway.id
  stage_name  = aws_api_gateway_stage.prod_stage.stage_name
  method_path = "*/*"  # Включить для всех методов

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}
