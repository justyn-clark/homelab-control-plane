# Secrets Handling

Do not commit secrets to this repository.

Use this directory only for local operator notes or temporary files that must remain outside version control.

Required practice:

- Copy each `env.example` to a local `.env`
- Generate strong secrets locally
- Keep Authelia user definitions in `stacks/auth/users_database.yml`
- Store backup repository credentials outside Git
- Rotate secrets if they are ever written to receipts, shell history, or logs

