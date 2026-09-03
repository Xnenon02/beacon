const form = document.getElementById("search-form");
const input = document.getElementById("search-input");
const results = document.getElementById("results");
const statusMessage = document.getElementById("status-message");

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const query = input.value.trim();
  if (!query) return;

  statusMessage.textContent = "Searching...";
  results.innerHTML = "";

  try {
    const response = await fetch(`/api/games/search?query=${encodeURIComponent(query)}`);
    if (!response.ok) {
      throw new Error(`Request failed: ${response.status}`);
    }

    const games = await response.json();

    if (games.length === 0) {
      statusMessage.textContent = `No games found for "${query}".`;
      return;
    }

    statusMessage.textContent = "";
    for (const game of games) {
      results.appendChild(renderCard(game));
    }
  } catch (error) {
    statusMessage.textContent = `Something went wrong: ${error.message}`;
  }
});

function renderCard(game) {
  const card = document.createElement("article");
  card.className = "card";

  const image = game.headerImage
    ? `<img src="${game.headerImage}" alt="${game.name}" class="card-image" />`
    : "";

  const playerCount =
    game.playerCount !== null && game.playerCount !== undefined
      ? `${game.playerCount.toLocaleString()} playing now`
      : "Player count unavailable";

  const description = game.shortDescription || "No description available.";

  card.innerHTML = `
    ${image}
    <div class="card-body">
      <h2>${game.name}</h2>
      <p class="price">${game.priceDisplay}</p>
      <p class="players">${playerCount}</p>
      <p class="description">${description}</p>
    </div>
  `;

  return card;
}
