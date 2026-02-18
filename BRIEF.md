# Project Brief

## Overview
Swimlanes is a Trello clone built with Ruby on Rails 8. Users can create multiple boards, each containing swimlanes (lists/columns) with cards that can be dragged to reorder within a lane or moved between lanes. Features include card details (descriptions, due dates, labels, checklists), board sharing between existing users, real-time updates via ActionCable, and customizable board backgrounds with colors and gradients.

## Tech Stack
- Ruby on Rails 8
- SQLite (local development)
- Hotwire / Turbo / Stimulus
- Tailwind CSS
- ActionCable for real-time updates
- Simple drag-and-drop library (e.g., SortableJS)
- Rails 8 built-in authentication generator

## Features (Priority Order)

1. **Project Setup & Authentication** — Rails 8 app scaffold with built-in auth (sign up, log in, log out)
2. **Board CRUD** — Create, read, update, delete boards; boards listing as landing page
3. **Swimlanes** — Columns within a board; create, edit, delete, reorder lanes
4. **Cards** — Create, edit, delete cards within lanes; drag-and-drop to reorder and move between lanes
5. **Card Details** — Descriptions, due dates, labels, and checklists on cards
6. **Board Sharing** — Share boards with existing users (no invite system needed)
7. **Real-Time Updates** — Live updates via ActionCable so collaborators see changes instantly
8. **Board Backgrounds** — Customizable board backgrounds with colors and gradients (no image uploads)

## Constraints
- Rails 8 with built-in authentication (no Devise)
- No Docker
- No deployment target yet
- SQLite for local development
- No image uploads — board backgrounds limited to colors and gradients
- Keep drag-and-drop implementation simple

## Testing
- Minitest for unit and integration tests
- Playwright for end-to-end testing

## Definition of Done
~6 phases for MVP, complete when all features above work with tests passing:
- Phase 1: Project setup, authentication, board CRUD
- Phase 2: Swimlanes and cards with drag-and-drop
- Phase 3: Card details (descriptions, due dates, labels, checklists)
- Phase 4: Board sharing between users
- Phase 5: Real-time updates via ActionCable
- Phase 6: Board background customization (colors/gradients)
