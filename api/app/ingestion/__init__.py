"""Phase 4 ingestion: document intelligence for the admin content pipeline.

extract (files -> text) -> chunking -> ai (pluggable providers) -> quality
(deterministic gate) -> pipeline (job orchestration + publish/rollback).
Nothing in here publishes: publishing is a human-triggered call.
"""
