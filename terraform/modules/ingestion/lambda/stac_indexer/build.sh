#!/bin/bash
# Build script for stac_indexer Lambda with dependencies

rm -rf package
mkdir -p package
pip install -r requirements.txt -t package/
cp handler.py package/
cd package
zip -r ../stac_indexer_with_deps.zip .
cd ..
rm -rf package
