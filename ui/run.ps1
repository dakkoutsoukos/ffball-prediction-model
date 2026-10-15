# Start the FFball app locally (http://127.0.0.1:8501). Local only; see ui/README.md.
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot
uv sync --frozen
uv run streamlit run app.py --server.address 127.0.0.1 --browser.gatherUsageStats false
