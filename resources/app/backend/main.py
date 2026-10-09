"""Kanban-App backend.

Reads short-lived PostgreSQL credentials from the file that Vault Agent writes
(/vault/secrets/db-creds). The file is read on every request, so when Vault
rotates the credentials the app picks up the new user without a restart.
"""
import os
from pathlib import Path

import psycopg
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

CLUSTER = os.getenv("CLUSTER_NAME", "unknown")
CREDS_FILE = Path(os.getenv("DB_CREDS_FILE", "/vault/secrets/db-creds"))
DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_NAME = os.getenv("DB_NAME", "kanban")
SSL_ROOT = os.getenv("DB_SSLROOTCERT", "/etc/db-ca/ca.crt")
STATUSES = {"todo", "doing", "done"}

app = FastAPI(title="Kanban-App")


class NewTask(BaseModel):
    title: str


class MoveTask(BaseModel):
    status: str


def read_creds():
    creds = {}
    for line in CREDS_FILE.read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            creds[key.strip()] = value.strip()
    return creds["DB_USER"], creds["DB_PASS"]


def connect():
    try:
        user, password = read_creds()
        conn = psycopg.connect(
            host=DB_HOST, dbname=DB_NAME, user=user, password=password,
            sslmode="verify-full", sslrootcert=SSL_ROOT, connect_timeout=5,
        )
        return conn, user
    except Exception as exc:  # show the reason in the API response (lab only)
        raise HTTPException(status_code=503, detail=f"database unavailable: {exc}") from exc


@app.get("/api/health")
def health():
    return {"status": "ok", "cluster": CLUSTER}


@app.get("/api/tasks")
def list_tasks():
    conn, user = connect()
    with conn:
        rows = conn.execute("SELECT id, title, status FROM tasks ORDER BY id").fetchall()
    return {
        "cluster": CLUSTER,
        "db_user": user,
        "tasks": [{"id": r[0], "title": r[1], "status": r[2]} for r in rows],
    }


@app.post("/api/tasks", status_code=201)
def add_task(task: NewTask):
    title = task.title.strip()
    if not title:
        raise HTTPException(status_code=400, detail="title is required")
    conn, _ = connect()
    with conn:
        new_id = conn.execute(
            "INSERT INTO tasks (title) VALUES (%s) RETURNING id", (title,)
        ).fetchone()[0]
    return {"id": new_id, "cluster": CLUSTER}


@app.put("/api/tasks/{task_id}")
def move_task(task_id: int, move: MoveTask):
    if move.status not in STATUSES:
        raise HTTPException(status_code=400, detail="status must be todo, doing or done")
    conn, _ = connect()
    with conn:
        conn.execute("UPDATE tasks SET status = %s WHERE id = %s", (move.status, task_id))
    return {"id": task_id, "status": move.status, "cluster": CLUSTER}


@app.delete("/api/tasks/{task_id}")
def delete_task(task_id: int):
    conn, _ = connect()
    with conn:
        conn.execute("DELETE FROM tasks WHERE id = %s", (task_id,))
    return {"deleted": task_id, "cluster": CLUSTER}
