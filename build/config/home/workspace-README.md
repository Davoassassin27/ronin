# Workspace

Este directorio es para proyectos. No instalar paquetes Python globalmente:
usar `uv` y entornos por proyecto.

```bash
cd ~/workspace
uv init mi-proyecto
cd mi-proyecto
uv add pandas polars duckdb
uv run python -c "import pandas; print(pandas.__version__)"
```

Modelos locales:

```bash
ollama list
ollama run qwen2.5:0.5b "ping"
# Los modelos viven en ~/ai-models/ollama
```

Docker:

```bash
docker run --rm hello-world
docker info --format '{{.DockerRootDir}}'
```

Hardware:

```bash
cat /var/log/hw-adapt-last.json | jq .
hyprctl monitors
vulkaninfo --summary
```
