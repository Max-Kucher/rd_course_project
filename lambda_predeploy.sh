#!/bin/bash

# Переменная для директории, куда будут сохраняться ZIP-архивы
OUTPUT_DIR="lambda_zip"

# Создаем директорию для ZIP-архивов, если она не существует
mkdir -p $OUTPUT_DIR

echo "Упаковка create_table_lambda..."
cd create_table_lambda
zip -r ../$OUTPUT_DIR/create_table_lambda.zip .   # Упаковываем все в ZIP
cd ..

# Упаковываем post_handler в ZIP (с зависимостями)
echo "Упаковка post_handler..."
cd post_handler
zip -r ../$OUTPUT_DIR/post_handler.zip .   # Упаковываем все в ZIP
cd ..

# Упаковываем get_handler в ZIP (с зависимостями)
echo "Упаковка get_handler..."
cd get_handler
zip -r ../$OUTPUT_DIR/get_handler.zip .   # Упаковываем все в ZIP
cd ..

# Проверяем, нужно ли создавать слой для pg (если он используется отдельно)
LAYER_DIR="lambda_layer/nodejs"
if [ -d "$LAYER_DIR" ]; then
    echo "Упаковка слоя с зависимостями..."
    cd lambda_layer
    zip -r ../$OUTPUT_DIR/lambda_pg_layer.zip .  # Упаковываем слой в ZIP
    cd ..
fi

echo "Lambda-функции и зависимости упакованы в $OUTPUT_DIR"
