import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static values = {
    url: String,
    swimlaneId: Number
  }

  connect() {
    this.sortable = Sortable.create(this.element, {
      group: "cards",
      animation: 150,
      ghostClass: "opacity-50",
      onEnd: this.onEnd.bind(this)
    })
  }

  disconnect() {
    this.sortable?.destroy()
  }

  onEnd(event) {
    const cardId = event.item.dataset.cardId
    const position = event.newIndex

    // Use the destination container's reorder URL
    const baseUrl = event.to.dataset.sortableUrlValue
    const reorderUrl = baseUrl.replace('/cards', '/cards/reorder')

    fetch(reorderUrl, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ card_id: cardId, position: position })
    })
      .then(response => {
        if (!response.ok) {
          event.from.insertBefore(event.item, event.from.children[event.oldIndex] || null)
        }
      })
      .catch(() => {
        event.from.insertBefore(event.item, event.from.children[event.oldIndex] || null)
      })
  }
}
