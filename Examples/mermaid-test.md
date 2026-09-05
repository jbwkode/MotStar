# Mermaid & editor test

## Flowchart

```mermaid
flowchart LR
    A[Write Markdown] --> B[Preview]
    B -->|Edit| C[Save]
    C --> B
```

## Sequence diagram

```mermaid
sequenceDiagram
    participant You
    participant MotStar
    You->>MotStar: type in editor
    MotStar-->>You: formatted preview
    You->>MotStar: ⌘S
```

## GFM kitchen sink

| Feature | Support |
| --- | --- |
| Tables | ✅ |
| ~~Strikethrough~~ | ✅ |
| `inline code` | ✅ |
| Task list | ✅ |

- [x] Created a Markdown file
- [x] Edited it in MotStar
- [ ] Tried Mermaid yet

> Block quote with **formatting**.

```python
def hello():
    return "world"
```

![Relative image](pic.png)
