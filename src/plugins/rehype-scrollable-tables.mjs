function wrapTables(node) {
  if (!Array.isArray(node.children)) {
    return;
  }

  for (let index = 0; index < node.children.length; index++) {
    const child = node.children[index];

    wrapTables(child);

    if (child.type === "element" && child.tagName === "table") {
      node.children[index] = {
        type: "element",
        tagName: "div",
        properties: {
          className: ["table-scroll"],
          tabIndex: 0,
          role: "region",
          ariaLabel: "Data table",
        },
        children: [child],
      };
    }
  }
}

export default function rehypeScrollableTables() {
  return wrapTables;
}
