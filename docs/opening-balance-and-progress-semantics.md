# Opening Balance and Progress Semantics

## Opening balance

ยอดตั้งต้นของบัญชีเป็นฐานของยอดเงินจริง ไม่ใช่รายรับในรอบเงินเดือน และไม่สร้าง transaction.

## Opening installment progress

ยอดที่จ่ายก่อนเริ่มติดตามเป็น historical progress ของรายการผ่อน เก็บแยกตาม profile และ installment ใน `profile_settings`. ค่านี้ใช้คำนวณ paid, remaining และจำนวนงวดโดยประมาณเท่านั้น ไม่สร้าง expense, ไม่ลดบัญชี และไม่ลด forecast รอบปัจจุบัน.

ตัวอย่าง 27,000 / จ่ายก่อนเริ่ม 16,000 / งวดละ 1,000 ต้องได้ remaining 11,000 และประมาณ 11 งวด โดยยอดเงินจริงไม่เปลี่ยน.

การจ่ายหลังเริ่มติดตามต้องสร้าง transaction จริงและ linkage ของ commitment payment. การแก้ ลบ หรือ restore transaction ดังกล่าวจึงเปลี่ยน progress ตาม ledger.

