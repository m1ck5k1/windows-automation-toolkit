# Unified Digital Signage Imaging Workflow (2026)

## Phase 1: Driver Acquisition & Validation
- [ ] **Download Driver Pack:**
  - **Source:** SCCM Package For Windows 10 64-bit (Version 1803, 1809, 1903) - ThinkCentre Systems (2.647GB).
  - **Release Date:** 05 Sep 2019.
  - **Status:** Recommended.
- [ ] **Extract & Organize:**
  - Run the `.exe` (Self-Extractor).
  - Target Path on Host Machine: `dev/clonezilla/drivers/Lenovo/M710q`.
  - *Verify:* Ensure the folder contains strictly `.inf`, `.cat`, `.sys` files (or subfolders thereof). remove any bloatware `.exe` installers if present.

## Phase 2: Reference Machine Preparation (`m710q-dev`)
- [ ] **Clean OS Install:**
  - Install **Windows 10/11 IoT Enterprise LTSC**.
  - **CRITICAL:** Do NOT connect to the internet during OOBE.
- [ ] **Enter Audit Mode:**
  - At the "Region Selection" screen, press `CTRL + SHIFT + F3`.
  - System reboots as `Administrator`.
- [ ] **Driver Injection (Manual):**
  - Copy `drivers/Lenovo/M710q` to `C:\DRIVERS\Lenovo\M710q`.
  - Run PowerShell (Admin):
    ```powershell
    Get-ChildItem "C:\DRIVERS\Lenovo\M710q" -Recurse -Filter "*.inf" | ForEach-Object { PNPUtil.exe /add-driver $_.FullName /install }
    ```
- [ ] **Verify Device Manager:**
  - Ensure no "Unknown Devices" remain.
  - Check Graphics (Intel HD 630), Audio, and LAN.

## Phase 3: Sysprep & Capture
- [ ] **Copy Automation Scripts:**
  - Place `setupcomplete.cmd` in `C:\Windows\Setup\Scripts`.
  - Place `unattend.xml` in `C:\Windows\System32\Sysprep`.
- [ ] **Run Sysprep:**
  - Command: `sysprep /generalize /oobe /shutdown /unattend:unattend.xml`
- [ ] **Capture with Clonezilla:**
  - **Mode:** Expert.
  - **Parameters:** `-q2`, `-c`, `-j2`, `-z1p`, `-i`, `-sfsck`, `-senc`, `-p true`.
  - **Key Flag:** `-fsck-src-part-y` (Check source filesystem).

## Phase 4: Deployment & Validation
- [ ] **Deploy to Target:**
  - **Mode:** Expert.
  - **Parameters:** `-icds` (Ignore cylinder check), `-k1` (Create partition table proportionally).
- [ ] **First Boot:**
  - Verify `setupcomplete.cmd` runs.
  - Verify drivers persist.
  - Verify Hostname randomization (if configured).
