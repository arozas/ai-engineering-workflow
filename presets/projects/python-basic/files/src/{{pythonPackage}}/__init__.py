def greet(name: str) -> str:
    normalized = name.strip()
    if not normalized:
        raise ValueError("name must be a non-empty string")
    return f"Hello, {normalized}!"
