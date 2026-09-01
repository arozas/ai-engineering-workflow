export function greet(name) {
  if (typeof name !== "string" || name.trim() === "") {
    throw new TypeError("name must be a non-empty string");
  }

  return `Hello, ${name.trim()}!`;
}
