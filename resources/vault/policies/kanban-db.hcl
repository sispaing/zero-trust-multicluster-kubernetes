# The Kanban backend may only read its own short-lived DB credentials
path "database/creds/kanban-app" { capabilities = ["read"] }
