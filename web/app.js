// The chat window: each message goes to /api/ask on the same address
// (CloudFront sends /api/* to Lambda) and the answer is added below it.
// textContent, never innerHTML: replies are shown as text, so nothing in them
// can run as code.
document.addEventListener("DOMContentLoaded", () => {
  const messages = document.getElementById("messages");
  const question = document.getElementById("question");
  const send = document.getElementById("send");
  const problems = {
    422: "Messages must be 1 to 1,000 characters.",
    502: "The AI model could not answer right now; try again in a moment.",
    503: "The AI answer is not set up yet.",
  };
  const sources = { weather: "via Weather (Open-Meteo REST API)" };

  function add(role, text) {
    const message = document.createElement("div");
    message.className = `msg ${role}`;
    const bubble = document.createElement("div");
    bubble.className = "bubble";
    bubble.textContent = text;
    message.append(bubble);
    messages.append(message);
    messages.scrollTop = messages.scrollHeight;
    return { message, bubble };
  }

  async function ask() {
    const text = question.value.trim();
    if (!text || send.disabled) return;
    question.value = "";
    add("user", text);
    const reply = add("bot", "Thinking...");
    send.disabled = true;
    try {
      const body = JSON.stringify({ question: text });
      // CloudFront signs every request to the API, and for a POST Lambda also
      // needs the SHA-256 of the body, which only the browser can work out.
      const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body));
      const hash = Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
      const response = await fetch("/api/ask", {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-amz-content-sha256": hash },
        body,
      });
      if (!response.ok) {
        throw new Error(problems[response.status] || `The API answered ${response.status}.`);
      }
      reply.bubble.textContent = "";
      const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        reply.bubble.textContent += value;
        messages.scrollTop = messages.scrollHeight;
      }
      if (!reply.bubble.textContent) {
        throw new Error("The answer came back empty.");
      }
      // Which service answered, from the X-Tools-Used header (empty: the model alone).
      const used = (response.headers.get("X-Tools-Used") || "").split(",").filter(Boolean);
      for (const name of used) {
        const via = document.createElement("div");
        via.className = "via";
        via.textContent = sources[name] || `via ${name}`;
        reply.message.append(via);
      }
    } catch (error) {
      reply.message.classList.add("error");
      reply.bubble.textContent = `Sorry, no answer. ${error.message}`;
    } finally {
      send.disabled = false;
      question.focus();
    }
  }

  send.addEventListener("click", ask);
  // Enter sends; Shift+Enter starts a new line.
  question.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      ask();
    }
  });
  question.focus();
});
