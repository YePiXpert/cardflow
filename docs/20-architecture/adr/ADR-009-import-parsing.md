# ADR-009 导入解析：文本层优先，OCR 兜底，许可证友好

状态：已接受 · 2026-10-16

决策：服务端 pypdf/pdfplumber 读文本层；无文本层用 rapidocr 3.x（Apache-2.0，CPU onnxruntime）；设备端截图用 ML Kit 中文文本识别；CSV 用模板映射；.eml 用 Python 标准库解析。不用 pymupdf（AGPL）与 Syncfusion（商业条件）。解析器版本写入每个候选。
后果：中文 OCR 准确率需 M1 样本集验证；加密 PDF 密码仅内存使用。
