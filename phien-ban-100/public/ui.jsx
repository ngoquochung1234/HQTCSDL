import React from 'react';
import {createRoot} from 'react-dom/client';
import {flushSync} from 'react-dom';

// Existing escaped HTML view templates are retained while React owns the
// screen lifecycle. Form and table behaviors use the shared event delegates.
function CruiseScreen({html}) {
 return <div className="cruise-screen" dangerouslySetInnerHTML={{__html:html}} />;
}
let root;
export function renderContent(html) {
 root ??= createRoot(document.getElementById('content'));
 flushSync(()=>root.render(<CruiseScreen html={html}/>));
}
