# priv/repo/seeds.exs
# Seed script for FlyRank Social Media Studio
alias FlyrankCapstoneSocialStudio.Content
alias FlyrankCapstoneSocialStudio.Content.Post
alias FlyrankCapstoneSocialStudio.Publishing.Slot
alias FlyrankCapstoneSocialStudio.Publishing.PublishAttempt
alias FlyrankCapstoneSocialStudio.Repo

IO.puts("--> Seeding database with sample capstone data...")

# Check if sample post already exists to maintain idempotency
existing = Repo.get_by(Post, title: "Building Resilient Distributed Systems with Elixir")

if is_nil(existing) do
  # 1. Ingest Sample Long-form Post
  {:ok, post} =
    Content.create_post(%{
      title: "Building Resilient Distributed Systems with Elixir",
      source_type: "markdown",
      content: """
      Elixir and the BEAM VM provide unmatched primitives for building distributed, fault-tolerant applications.
      By utilizing lightweight processes, supervision trees, and persistent queue architectures like Oban,
      teams can build self-healing background jobs that survive unhandled exceptions and server restarts.

      Key principles include:
      1. Letting workers crash safely while supervisors maintain system invariants.
      2. Enforcing database-level unique constraints for genuine idempotency.
      3. Applying clean adapter seams to decouple business logic from external API providers.
      """,
      total_ai_cost: Decimal.new("0.000450")
    })

  IO.puts("    Created Post ##{post.id}: #{post.title}")

  # 2. Seed Mock X Variant (Approved & Scheduled)
  {:ok, var_x} =
    Content.create_variant(%{
      post_id: post.id,
      platform: "mock_x",
      content: "Building distributed systems? The BEAM VM + Oban gives you supervision trees and durable queues. Let it crash safely. #elixir #backend",
      status: "approved",
      model_used: "gemini-2.5-flash",
      prompt_tokens: 180,
      completion_tokens: 45,
      total_tokens: 225,
      generation_cost: Decimal.new("0.000150")
    })

  IO.puts("    Created approved Variant ##{var_x.id} (mock_x)")

  # 3. Seed Scheduled Slot for Mock X Variant
  scheduled_time = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
  {:ok, slot} =
    Repo.insert(%Slot{
      variant_id: var_x.id,
      scheduled_at: scheduled_time,
      status: "pending",
      idempotency_key: "seed-slot-#{post.id}-x"
    })

  IO.puts("    Created pending Slot ##{slot.id} scheduled for #{scheduled_time}")

  # 4. Seed Mock LinkedIn Variant (Draft awaiting review)
  {:ok, var_li} =
    Content.create_variant(%{
      post_id: post.id,
      platform: "mock_linkedin",
      content: """
      Why are engineering teams migrating mission-critical ingestion workflows to Elixir?

      1. Fault-Tolerant Supervisors: Background tasks recover instantly without taking down the node.
      2. True Idempotency: Distributed retries survive network partitions without duplicate dispatches.
      3. Clean Adapter Seams: External platform APIs are swappable through strict behaviours.

      How does your team handle idempotent background jobs? Let's discuss in the comments. #engineering #elixir #architecture
      """,
      status: "draft",
      model_used: "gemini-2.5-flash",
      prompt_tokens: 220,
      completion_tokens: 85,
      total_tokens: 305,
      generation_cost: Decimal.new("0.000300")
    })

  IO.puts("    Created draft Variant ##{var_li.id} (mock_linkedin)")

  # 5. Seed Telegram Variant (Already Published with Audit History)
  {:ok, var_tg} =
    Content.create_variant(%{
      post_id: post.id,
      platform: "telegram",
      content: "🚀 New Guide Published: Building resilient background jobs with Elixir and Oban.\n\nCheck it out here! #dev #elixir",
      status: "published",
      model_used: "gemini-2.5-flash",
      prompt_tokens: 150,
      completion_tokens: 35,
      total_tokens: 185,
      generation_cost: Decimal.new("0.000100")
    })

  published_time = DateTime.utc_now() |> DateTime.add(-1800, :second) |> DateTime.truncate(:second)
  {:ok, past_slot} =
    Repo.insert(%Slot{
      variant_id: var_tg.id,
      scheduled_at: published_time,
      status: "published",
      idempotency_key: "seed-slot-#{post.id}-tg"
    })

  {:ok, _attempt} =
    Repo.insert(%PublishAttempt{
      slot_id: past_slot.id,
      adapter_name: "FlyrankCapstoneSocialStudio.Publishing.Adapters.Telegram",
      status: "success",
      external_post_id: "tg_msg_8849102",
      response_payload: %{"ok" => true, "result" => %{"message_id" => 8849102}}
    })

  IO.puts("    Created published Variant ##{var_tg.id} (telegram) with audit history")
  IO.puts("--> Database seeding complete! ✅")
else
  IO.puts("    Sample post already seeded. Skipping.")
end
