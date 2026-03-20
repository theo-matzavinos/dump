function escapeHtml(value) {
	return value
		.replaceAll('&', '&amp;')
		.replaceAll('<', '&lt;')
		.replaceAll('>', '&gt;')
		.replaceAll('"', '&quot;');
}

function transformChildren(node) {
	if (!node || !Array.isArray(node.children)) {
		return;
	}

	node.children = node.children.map((child) => {
		transformChildren(child);

		if (child.type !== 'code' || child.lang !== 'mermaid') {
			return child;
		}

		const source = child.value.trim();
		const escapedSource = escapeHtml(source);

		return {
			type: 'html',
			value: `<figure class="diagram diagram-mermaid"><div class="mermaid" data-mermaid-source="${escapedSource}">${escapedSource}</div></figure>`,
		};
	});
}

export default function remarkMermaid() {
	return function transformer(tree) {
		transformChildren(tree);
	};
}
