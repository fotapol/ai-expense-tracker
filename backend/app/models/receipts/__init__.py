"""Receipt ingestion models."""

from app.models.receipts.receipt import Receipt, ReceiptBase
from app.models.receipts.receipt_extraction import ReceiptExtraction

__all__ = ["Receipt", "ReceiptBase", "ReceiptExtraction"]
