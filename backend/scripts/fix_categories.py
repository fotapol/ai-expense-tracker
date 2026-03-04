"""Temp script to fix existing UNCATEGORIZED transactions by re-reading the extraction."""

import sys
import os
import asyncio
import json

# Add backend to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.core.db import engine
from sqlmodel import Session, select
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.models.receipts.receipt_extraction import ReceiptExtraction
from app.worker.receipt_processor import _get_uncategorized_category_id, _resolve_category_id

def run():
    with Session(engine) as session:
        uncategorized_id = _get_uncategorized_category_id(session)
        print(f"UNCATEGORIZED ID is {uncategorized_id}")
        
        # Find all items that are UNCATEGORIZED
        items = session.exec(
            select(TransactionItem).where(TransactionItem.category_id == uncategorized_id)
        ).all()
        
        print(f"Found {len(items)} uncategorized items to fix.")
        
        fixed_count = 0
        for item in items:
            tx = session.exec(select(Transaction).where(Transaction.id == item.transaction_id)).first()
            if not tx or not tx.receipt_id:
                continue
                
            extraction = session.exec(
                select(ReceiptExtraction).where(ReceiptExtraction.receipt_id == tx.receipt_id)
            ).first()
            
            if not extraction:
                continue
                
            data = extraction.structured_json
            if isinstance(data, str):
                data = json.loads(data)
                
            # Find matching item in json
            # We match by line_no if exact, or just assume order
            json_items = data.get("items", [])
            target_json_item = None
            for ji in json_items:
                if ji.get("line_no") == item.line_no or ji.get("description") == item.description:
                    target_json_item = ji
                    break
                    
            if target_json_item:
                cat_code = target_json_item.get("category_code")
                if cat_code:
                    new_cat_id = _resolve_category_id(session, cat_code, uncategorized_id)
                    item.category_id = new_cat_id
                    session.add(item)
                    fixed_count += 1
                    
        session.commit()
        print(f"Fixed {fixed_count} items!")

if __name__ == "__main__":
    run()
