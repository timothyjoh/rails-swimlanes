import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static values = {
    url: String,
    group: { type: String, default: "cards" },
    axis: { type: String, default: "" }
  }

  connect() {
    this.sortable = Sortable.create(this.element, {
      group: this.groupValue,
      animation: 150,
      ghostClass: "opacity-50",
      direction: this.axisValue === "x" ? "horizontal" : "vertical",
      onEnd: this.onEnd.bind(this)
    })
  }

  disconnect() {
    this.sortable?.destroy()
  }

  onEnd(event) {
    const item = event.item
    const position = event.newIndex
    const revertOnFailure = () => {
      event.from.insertBefore(item, event.from.children[event.oldIndex] || null)
    }

    let url, body

    if (item.dataset.cardId) {
      // Card reorder — post to destination swimlane's reorder URL
      const baseUrl = event.to.dataset.sortableUrlValue
      url = baseUrl + "/reorder"
      body = { card_id: item.dataset.cardId, position }
    } else if (item.dataset.swimlaneId) {
      // Swimlane reorder — post to board's swimlane reorder URL
      url = this.urlValue
      body = { swimlane_id: item.dataset.swimlaneId, position }
    } else {
      return
    }

    fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify(body)
    })
      .then(response => { if (!response.ok) revertOnFailure() })
      .catch(revertOnFailure)
  }
}
