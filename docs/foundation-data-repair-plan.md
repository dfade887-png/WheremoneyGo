# Foundation Data Repair Plan

Foundation build อาจเคยสร้าง expense จากช่องยอดที่จ่ายก่อนเริ่มติดตาม การแก้รุ่นนี้ไม่ลบหรือแก้ transaction เดิมอัตโนมัติ เพราะจำนวนเงินและข้อความเพียงอย่างเดียวไม่ใช่หลักฐานที่ปลอดภัยพอ.

แนวทาง repair ที่อนุญาตในอนาคต:

1. Backup ฐานข้อมูล v4 ก่อนทำรายการใด ๆ
2. ตรวจเฉพาะ transaction ที่มี deterministic linkage กับ legacy installment occurrence
3. แสดง preview ระบุ transaction, บัญชี และยอดที่จะคืน
4. ให้ผู้ใช้ยืนยันอย่างชัดเจน
5. ทำ unlink, soft delete และบันทึก opening progress ใน transaction เดียว
6. เขียน audit event และ recompute snapshot
7. Rollback ทั้งชุดเมื่อเกิดข้อผิดพลาด

ถ้าหลักฐานไม่ครบ ผู้ใช้ต้องแก้ผ่าน Transaction correction เอง ห้ามเดาจากยอด 16,000 บาทเพียงอย่างเดียว.

