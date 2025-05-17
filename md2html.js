const fs = require('fs');
const path = require('path');

// 手動進行Markdown轉HTML轉換
function markdownToHtml(markdown) {
  // 讀取Markdown內容，拆分為行
  const lines = markdown.split('\n');
  let html = '';
  let inList = false;
  let inOrderedList = false;
  let currentListType = null;
  
  // 添加HTML頭部
  html += `<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PowerNap 隱私政策</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            line-height: 1.6;
            padding: 20px;
            max-width: 800px;
            margin: 0 auto;
            color: #333;
        }
        h1 {
            color: #2c3e50;
            border-bottom: 1px solid #eee;
            padding-bottom: 10px;
        }
        h2 {
            color: #3498db;
            margin-top: 30px;
        }
        h3 {
            color: #2980b9;
        }
        ul, ol {
            padding-left: 25px;
        }
        a {
            color: #3498db;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        code {
            background-color: #f8f8f8;
            padding: 2px 4px;
            border-radius: 3px;
        }
        blockquote {
            border-left: 4px solid #ccc;
            padding-left: 15px;
            color: #666;
        }
        hr {
            border: 0;
            border-top: 1px solid #eee;
            margin: 20px 0;
        }
        .container {
            background-color: #fff;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        @media (prefers-color-scheme: dark) {
            body {
                background-color: #1a1a1a;
                color: #f0f0f0;
            }
            .container {
                background-color: #2d2d2d;
            }
            h1 {
                color: #f0f0f0;
                border-bottom-color: #444;
            }
            h2 {
                color: #3498db;
            }
            h3 {
                color: #5dade2;
            }
            a {
                color: #5dade2;
            }
            code {
                background-color: #3d3d3d;
            }
            blockquote {
                border-left-color: #555;
                color: #aaa;
            }
            hr {
                border-top-color: #444;
            }
        }
    </style>
</head>
<body>
<div class="container">
`;

  // 逐行處理Markdown
  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    
    // 處理標題
    if (line.startsWith('# ')) {
      html += `<h1>${line.substring(2)}</h1>\n`;
    } else if (line.startsWith('## ')) {
      html += `<h2>${line.substring(3)}</h2>\n`;
    } else if (line.startsWith('### ')) {
      html += `<h3>${line.substring(4)}</h3>\n`;
    } 
    // 處理列表
    else if (line.startsWith('- ')) {
      if (!inList || currentListType !== 'ul') {
        if (inList) html += '</ol>\n';
        html += '<ul>\n';
        inList = true;
        currentListType = 'ul';
      }
      html += `<li>${line.substring(2)}</li>\n`;
    }
    // 處理數字列表
    else if (/^\d+\.\s/.test(line)) {
      if (!inList || currentListType !== 'ol') {
        if (inList) html += '</ul>\n';
        html += '<ol>\n';
        inList = true;
        currentListType = 'ol';
      }
      html += `<li>${line.replace(/^\d+\.\s/, '')}</li>\n`;
    }
    // 處理水平線
    else if (line === '---') {
      if (inList) {
        html += currentListType === 'ul' ? '</ul>\n' : '</ol>\n';
        inList = false;
      }
      html += '<hr>\n';
    }
    // 處理空行
    else if (line.trim() === '') {
      if (inList) {
        html += currentListType === 'ul' ? '</ul>\n' : '</ol>\n';
        inList = false;
      }
      html += '<br>\n';
    }
    // 處理普通段落
    else {
      if (inList) {
        html += currentListType === 'ul' ? '</ul>\n' : '</ol>\n';
        inList = false;
      }
      
      // 處理粗體和斜體
      line = line.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
      line = line.replace(/\*(.*?)\*/g, '<em>$1</em>');
      
      // 處理鏈接
      line = line.replace(/\[(.*?)\]\((.*?)\)/g, '<a href="$2">$1</a>');
      
      html += `<p>${line}</p>\n`;
    }
  }
  
  // 關閉最後可能開啟的列表
  if (inList) {
    html += currentListType === 'ul' ? '</ul>\n' : '</ol>\n';
  }
  
  // 添加HTML尾部
  html += `</div>
</body>
</html>`;

  return html;
}

// 讀取Markdown文件
const markdownPath = 'docs/PrivacyPolicy.md';
const htmlPath = 'docs/PrivacyPolicy.html';

try {
  const markdown = fs.readFileSync(markdownPath, 'utf8');
  const html = markdownToHtml(markdown);
  
  fs.writeFileSync(htmlPath, html, 'utf8');
  console.log(`已成功將 ${markdownPath} 轉換為 ${htmlPath}`);
} catch (error) {
  console.error('轉換過程中發生錯誤:', error);
} 