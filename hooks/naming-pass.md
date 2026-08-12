Before you finish: one quick naming-and-comments pass over the code you just
changed. Only the lines you touched this turn — do not review the rest of the
file, do not fix unrelated things, and do not start new work.

Two questions, in this order:

1. **Names.** Is any name you introduced too short to carry its meaning — a
   single word, an unexplained abbreviation, or a bare `data` / `result` /
   `item` / `tmp` / `val` — where a two-word name would say what it actually
   holds? Reach for the specific noun: `rows` over `data`, `parsedRows` over
   `rows` once a raw set is also in scope, `retryDelayMs` over `delay`. A
   short name is fine when its scope is two lines long and its type is obvious;
   it is not fine when it outlives half a screen.

2. **Comments.** Is any comment you wrote saying what a name should have said
   on its own? If renaming the thing makes the comment redundant, rename it and
   delete the comment. Keep every comment that explains *why* — a constraint, a
   workaround, a non-obvious reason, a link to an issue. Those are not naming
   failures and must survive this pass.

Apply the changes you are confident about, and apply them quietly. A rename
only earns its diff if the new name is clearly better; churn costs more than a
short name that reads fine in context. Renaming anything exported or otherwise
public is out of scope here — mention it instead of doing it.

If nothing needs changing, reply `naming pass: clean` and stop. Do not write a
report, do not summarise what you checked, and do not re-explain the work you
already described.
