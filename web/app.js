// Calls the API on the same address (CloudFront sends /api/* to Lambda) and
// shows the reply. textContent, never innerHTML: the reply is shown as text,
// so nothing in it can run as code.
document.addEventListener("DOMContentLoaded", () => {
  const button = document.getElementById("hello");
  const reply = document.getElementById("reply");

  button.addEventListener("click", async () => {
    button.disabled = true;
    reply.classList.remove("error");
    reply.textContent = "Asking the API...";
    try {
      const response = await fetch("/api/hello", { headers: { Accept: "application/json" } });
      if (!response.ok) {
        throw new Error(`The API answered ${response.status}.`);
      }
      const data = await response.json();
      reply.textContent = data.message;
    } catch (error) {
      reply.classList.add("error");
      reply.textContent = `Sorry, the API could not be reached. ${error.message}`;
    } finally {
      button.disabled = false;
    }
  });
});
