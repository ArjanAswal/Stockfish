#!/bin/bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

exec flutter test integration_test/app_test.dart
