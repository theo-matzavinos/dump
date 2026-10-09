// Call once, after the example's interactions and layout checks have completed.
export function reportChecks(checks) {
  if (document.getElementById("article-check-result")) {
    throw new Error("The article check result has already been reported.");
  }

  const result = {
    viewport: {
      width: window.innerWidth,
      height: window.innerHeight,
    },
    checks,
  };

  const output = document.createElement("pre");

  output.id = "article-check-result";
  output.textContent = JSON.stringify(result, null, 2);
  document.body.append(output);

  return result;
}
