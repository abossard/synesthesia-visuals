# Tachikoma Runtime Config

Primary config (committed in repo):

`/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/tachikoma.json`

Lookup order:

1. `SWIFTVJ_TACHIKOMA_CONFIG` (if set)
2. repo-root `tachikoma.json`
3. current-working-directory `tachikoma.json`
4. fallback `~/Library/Application Support/SwiftVJ/tachikoma.json`

Default committed config:

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
