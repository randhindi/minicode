// Fetch a user and greet them
import { readFile } from "node:fs/promises";

export async function greet(id) {
  const res = await fetch(`https://api.example.com/users/${id}`);
  const { name = 'friend' } = await res.json();
  console.log(`Hello, ${name}!`, 42, null, undefined);
  return class Greeter extends Object {};
}
