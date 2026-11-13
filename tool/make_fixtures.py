import os, zipfile, io

OUT = "test/fixtures"
os.makedirs(OUT, exist_ok=True)

txt = """斗破苍穹

第一章 陨落的天才
“斗之力，三段！”
望着测验魔石碑上面闪亮得甚至有些刺眼的五个大字，少年面无表情。
这是他第三次参加测验了，依然没有起色。

第二章 斗气大陆
斗气大陆，没有花哨的魔法，有的只是繁衍到巅峰的斗气。
在这里，斗气就是一切。

第三章 客人
萧家大厅里，客人已经等候多时了。
"""
open(f"{OUT}/斗破苍穹 作者：天蚕土豆.txt", "w", encoding="utf-8").write(txt)

gbk_txt = "第一章 开始\n这是一本GBK编码的小说。\n第二章 继续\n内容还在继续。\n"
open(f"{OUT}/gbk小说.txt", "wb").write(gbk_txt.encode("gbk"))

container = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>"""

opf = """<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>测试书</dc:title>
    <dc:creator>测试作者</dc:creator>
    <dc:language>zh-CN</dc:language>
    <meta name="cover" content="cover-img"/>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover-img" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>"""

ch1 = """<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title><style>p{color:red}</style></head>
<body><h1>第一章 启程</h1>
<p>山道上起了雾，他把行囊又束紧了一些。</p>
<p>“往北走三天，就到了。”<br/>老人这样说。</p>
<p>&amp; 就这样出发了&hellip;</p>
</body></html>"""

ch2 = """<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第二章</title></head>
<body><h2>第二章 夜宿</h2><p>客栈的灯很暗，他读完了半本书。</p></body></html>"""

jpeg = bytes([0xFF,0xD8,0xFF,0xE0]) + b"\x00"*64 + bytes([0xFF,0xD9])

zf = zipfile.ZipFile(f"{OUT}/测试书.epub", "w")
zf.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
zf.writestr("META-INF/container.xml", container)
zf.writestr("OEBPS/content.opf", opf)
zf.writestr("OEBPS/ch1.xhtml", ch1)
zf.writestr("OEBPS/ch2.xhtml", ch2)
zf.writestr("OEBPS/cover.jpg", jpeg)
zf.close()
print("fixtures ok")
