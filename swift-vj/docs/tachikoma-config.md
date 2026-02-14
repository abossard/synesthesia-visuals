# Tachikoma Runtime Config

SwiftVJ reads LLM provider configuration from:

`~/Library/Application Support/SwiftVJ/tachikoma.json`

If the file is missing or invalid, SwiftVJ falls back to local LM Studio:

```json
{
  "songAnalysis": {
    "provider": "lmstudio",
    "model": "current",
    "baseURL": "http://localhost:1234/v1"
  },
  "shaderAnalysis": {
    "provider": "lmstudio",
    "model": "current",
    "baseURL": "http://localhost:1234/v1"
  }
}
```

Supported `provider` values:

- `lmstudio`
- `ollama`
- `openai`
- `anthropic`
- `azure_openai`

For `azure_openai`, use `model` as your deployment name and optionally provide:

- `azureResource`
- `azureEndpoint`
- `azureAPIVersion`
- `apiKey`
