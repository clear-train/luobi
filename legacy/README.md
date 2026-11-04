# legacy/ —— 早期原型，不再维护

这两个东西不是现在的应用。现在的应用在 **`luobi/`**，名字叫 **落笔**。

| 目录 | 是什么 | 为什么留在这里 |
| --- | --- | --- |
| `ulysses-lite.html` | 最早的单文件 HTML 写作器（浏览器里双击就能用） | 现在应用的界面和交互都是从它试出来的，当参照物 |
| `ulysses-shell/` | 一个 Swift + WKWebView 的壳，想给 HTML 版套个 `.app` | 没做成（本地 HTTP 服务那套太脆），直接改写了原生，留作教训 |

两者的数据都在浏览器 localStorage 或旧的 `~/Library/Application Support/UlyssesLite/` 里，和落笔的 `~/Library/Application Support/Luobi/` **不是同一份**，不会互相干扰。
