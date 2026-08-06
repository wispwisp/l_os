# CLAUDE.md

As far as I remember, I was working on my little operating system kernel but stopped at memory page allocations. I want to continue that work.

## Files to ignore
Ignore those files completely, as they are not your concern.
- build_claudecode_isolation_container.sh
- run_claudecode_isolation_container.sh
- claudecode.dockerfile
- check_grammar.sh

## Git authority
- Author name: `wisp`
- Author email: `forworkandtravel@yandex.ru`
- Commit style: short imperative subject (≤ 72 chars), body wrapped at 72,
  explain *why* not *what*. No AI-attribution trailers.

---

# Engineering Principles

## 1. Think Before Coding
- **Stop and ask** if requirements are ambiguous. Do not guess.
- **State assumptions explicitly** before writing any non-trivial code.
- **Present multiple interpretations** with tradeoffs if more than one valid approach exists.
- **Push back** if a requested change is over-engineered or adds unnecessary complexity.

## 2. Simplicity First
- Write the **minimum code** required to solve the task.
- Avoid speculative features, abstractions for single-use code, or "future-proofing."
- If a 200-line solution can be 50 lines, rewrite it.
- **Seniority Test**: If a senior engineer would call it "bloated," simplify it.

## 3. Surgical Changes
- **Touch only what is required.** Match existing code style perfectly.
- Do not "improve" adjacent code, refactor unrelated sections, or change formatting/quotes.
- **Preserve comments** you don't fully understand; do not delete them.
- Every line changed must trace directly to the current request.

## 4. Goal-Driven Execution
- Transform tasks into **verifiable goals** (e.g., "Write a failing test for [bug], then make it pass").
- Provide a brief plan for multi-step tasks before starting.
- **Loop until verified**: Do not declare success until you have run the relevant tests or verification steps.
