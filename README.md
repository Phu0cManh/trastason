## **1. [Fixing the INA3221 breakout board - Arduino Forum](https://forum.arduino.cc/t/fixing-the-ina3221-breakout-board/526947)**
Làm theo link trên, thêm bước tháo 3 R shunt đi
## **2. SCHEMATIC:**
- Tháo phần sau mạch UGREEN 300W
- Tìm các Rshunt(trở to có ghi R003, R005, R010)
- Kết nối mạch Ina với các Rshunt(đầu Rshunt nối với cuộn cảm là in+ còn lại là in-, chỉ dùng CH1,2 CH3 có vẻ bị lỗi cổng c1 dự định dùng ina226 cách làm tương tự ina3221)![alt text](z6934232724458_c35a5d1e1363b10820e51de448c3193d.jpg)
- SDA, SCL (2 mạch ina và oled) nối GPIO 21,22![alt text](z6934232728361_82cebfbb9baa0eb51fadfc112d9b7a1a.jpg)
- 5v ina nối 5v/vin esp
- GND nối chung với nhau

## **App build sẵn:** release\app-release.apk


## **Source code: app\lib\main.dart**
code dùng flutter

### NẾU CÓ GÌ THẮC MẮC VUI LÒNG LIÊN HỆ CLAUDE/COPILOT/GPT 😁