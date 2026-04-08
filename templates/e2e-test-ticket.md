---
id: 1
title: Add hello endpoint
status: ready
labels: [feature]
created: 2026-01-01
---
## Summary
Add a GET /hello endpoint that returns {"message": "hello"}.

## Requirements
- Backend: Create GET /hello returning JSON {"message": "hello"}
- Frontend: Add a "Hello" button that calls GET /hello and displays the response
- Tests: Verify GET /hello returns 200 with correct JSON body

## Acceptance Criteria
- [ ] GET /hello returns {"message": "hello"}
- [ ] Frontend button calls the endpoint
- [ ] Test passes
