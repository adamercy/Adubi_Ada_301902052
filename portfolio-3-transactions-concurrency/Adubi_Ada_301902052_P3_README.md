# Adubi_Ada_301902052 Portfolio 2: Transactions

In this portfolio I demonstrated PostgreSQL transactions on the AdaLink database, with one short example each for **commit**, **rollback**, **isolation** and **concurrency control**.

## Files

| File | Purpose |
| --- | --- |
| `Session_A_SQL_Script_Transactions.sql` | Steps run in the first pgAdmin Query Tool tab (Session A) |
| `Session_B_SQL_Script_Transactions.sql` | Steps run in the second tab (Session B), for E3 and E4 |
| `screenshots/` | Output of each step, named after the step labels |

## How I tested

I opened two Query Tool tabs on the `adalink` database. Each tab has its own connection, so they behave like two users working at the same time. I ran one labelled step at a time. Every example uses the stock of product 777 (Tecno Spark 20 Smartphone) in warehouse 2 (Lagos) and warehouse 5 (Kano), which the `[SETUP]` step set to 10 each.

## Results

| Example | What I did | Result | Evidence |
| --- | --- | --- | --- |
| E1 Commit | Moved 2 phones from Lagos to Kano in one transaction, then committed | Lagos 10 → 8, Kano 10 → 12 | [SETUP](screenshots/SETUP.png), [E1-1](screenshots/E1-1.png) |
| E2 Rollback | Started moving 5 phones, then rolled back | 3 and 17 inside the transaction; back to 8 and 12 after `ROLLBACK` | [E2-1](screenshots/E2-1.png), [E2-2](screenshots/E2-2.png) |
| E3 Isolation | A sold 1 phone without committing; B read the stock before and after A committed | A saw 7; B saw 8 until A committed, then 7 | [E3-1](screenshots/E3-1.png), [E3-2](screenshots/E3-2.png), [E3-4](screenshots/E3-4.png) |
| E4 Concurrency control | A and B each sold 1 phone from the same row at the same time | A saw 6; B waited until A committed, then finished at 5 | [E4-1](screenshots/E4-1.png), [waiting](screenshots/E4-2_waiting.png), [result](screenshots/E4-2_result.png) |

## What each example shows

**Commit.** A stock move needs two updates, one out of Lagos and one into Kano. Inside `BEGIN … COMMIT` they become one unit of work, saved together and permanently (atomicity and durability).

**Rollback.** Session A could see its half-finished move (3 and 17), but `ROLLBACK` undid both updates at once. An application uses this to cancel failed work, such as an abandoned checkout, without leaving broken data.

**Isolation.** Under PostgreSQL's default level, Read Committed, Session B never saw A's uncommitted sale (no dirty read). It saw the new stock only after A committed.

**Concurrency control.** If two customers buy the same phone at once, both could read 7 and write 6, losing a sale. PostgreSQL's row-level lock made Session B wait until A committed, then apply its update to A's result, so the stock ended at 5 and both sales counted.

