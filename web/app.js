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

  // Ask a question: the answer streams in and is added as it arrives.
  const askButton = document.getElementById("ask");
  const question = document.getElementById("question");
  const answer = document.getElementById("answer");
  const problems = {
    422: "Questions must be 1 to 1,000 characters.",
    429: "The daily question limit is reached; try again tomorrow.",
    503: "The AI answer is not set up yet.",
  };

  askButton.addEventListener("click", async () => {
    const text = question.value.trim();
    answer.classList.remove("error");
    if (!text) {
      answer.textContent = "Type a question first.";
      return;
    }
    askButton.disabled = true;
    answer.textContent = "Thinking...";
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
      answer.textContent = "";
      const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        answer.textContent += value;
      }
      if (!answer.textContent) {
        throw new Error("The answer came back empty.");
      }
    } catch (error) {
      answer.classList.add("error");
      answer.textContent = `Sorry, no answer. ${error.message}`;
    } finally {
      askButton.disabled = false;
    }
  });
});
