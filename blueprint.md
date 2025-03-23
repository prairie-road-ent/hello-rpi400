# Bare-Metal Assembly Program for a Raspberry Pi 400

This document explains how to write a bare‑metal ARM AArch64 assembly program that initializes a framebuffer and paints the entire screen red. We include the complete assembly source code (kernel.S), a corresponding linker script (linker.ld), and detailed instructions for compiling the code and preparing a bootable microSD card with the required firmware files (bootcode.bin, start4.elf, fixup4.dat) for the Raspberry Pi 400.

For context, this example assumes you are using a 7″ Elecrow display connected via HDMI. You can later modify the mailbox property calls to query the display’s native resolution if needed (using a “get physical display size” tag such as 0x40003).

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Assembly Source Code (kernel.S)](#assembly-source-code-kernels)
3. [Linker Script (linker.ld)](#linker-script-linkerld)
4. [Build Instructions](#build-instructions)
5. [MicroSD Card Preparation and Boot Setup](#microsd-card-preparation-and-boot-setup)
6. [Additional Considerations](#additional-considerations)
7. [Conclusion](#conclusion)

---

## Prerequisites

- **Cross-Compiler:** Install the `gcc-aarch64-none-elf` toolchain.
- **Linker Script Knowledge:** Understand that the linker script tells the linker where to load your code in memory.
- **Access to Firmware Files:** Obtain the required firmware files for the Raspberry Pi 400: `bootcode.bin`, `start4.elf`, and `fixup4.dat`.
- **MicroSD Preparation Tools:** Tools like `fdisk`, `mkfs.vfat` (Linux/macOS) or equivalent on Windows.
- **Basic CLI Skills:** Comfort with command-line tools for compiling, formatting, and copying files.

---

## Assembly Source Code (kernel.S)

Save the following code as `kernel.S`. Each section is commented to explain its purpose:

```assembly
    .section .text                     // Begin the code section.
    .global _start                     // Define the entry point for the bootloader.

_start:
    // ----------------------------------------------------------------
    // Step 1: Setup Mailbox Call
    // We want to communicate with the VideoCore firmware via the mailbox
    // property interface. Our mailbox_buffer (defined in .data) contains
    // our property message with tags to set the physical and virtual display
    // sizes, pixel depth, framebuffer allocation, and to obtain the pitch.
    // ----------------------------------------------------------------
    ldr x0, =mailbox_buffer            // Load the address of our mailbox message.
    bl  mailbox_call                   // Call the mailbox routine.
                                      // After return, mailbox_buffer holds the response.

    // ----------------------------------------------------------------
    // Step 2: Retrieve Framebuffer Parameters
    // The mailbox_buffer is updated with the response. We extract:
    //   - Display width (at offset 12 bytes)
    //   - Display height (at offset 16 bytes)
    //   - Pitch (bytes per line, at offset 20 bytes)
    //   - Framebuffer base address (at offset 28 bytes)
    // ----------------------------------------------------------------
    ldr w4, [mailbox_buffer, #12]      // w4 := physical display width (e.g. 800).
    ldr w5, [mailbox_buffer, #16]      // w5 := physical display height (e.g. 600).
    ldr w6, [mailbox_buffer, #20]      // w6 := pitch (bytes per row).
    ldr x3, [mailbox_buffer, #28]      // x3 := framebuffer base address.

    // ----------------------------------------------------------------
    // Step 3: Fill the Framebuffer with Red
    // For a 32-bpp framebuffer, each pixel is 4 bytes. We loop over all pixels,
    // storing the red color (0x00FF0000) in each.
    // ----------------------------------------------------------------
    mul w7, w4, w5                   // Compute total pixel count: width * height.
    mov w8, #0x00FF0000              // Set w8 to red color in ARGB format (alpha 0, full red).
fill_loop:
    str w8, [x3], #4                // Store red in current pixel and increment the pointer.
    subs w7, w7, #1                // Decrement pixel counter.
    bne fill_loop                  // Continue until all pixels are processed.

    // ----------------------------------------------------------------
    // Step 4: Infinite Loop to Prevent Exit
    // We loop indefinitely to keep the program running.
    // ----------------------------------------------------------------
infinite_loop:
    b infinite_loop                // Infinite loop.


// --------------------------------------------------------------------
// Mailbox Call Routine
// This subroutine communicates with the VideoCore firmware via the mailbox.
// It waits until the mailbox is available, writes our message address combined
// with the channel ID (8), and then waits for the response.
// --------------------------------------------------------------------
mailbox_call:
    // Wait for the mailbox to be ready for a write.
wait_mailbox:
    ldr x9, =MAILBOX_STATUS          // Load the mailbox status register address.
    ldr w10, [x9]                    // Read the mailbox status.
    and w10, w10, #0x80000000         // Check if the mailbox is full (flag bit).
    cbnz w10, wait_mailbox           // If full, loop until space is available.

    // Write the mailbox message with the channel identifier.
    ldr x11, =MAILBOX_WRITE         // Load the mailbox write register address.
    orr x12, x0, #8                 // Combine message address (in x0) with channel id (8).
    str x12, [x11]                  // Write the combined value to the mailbox.

    // Wait for the response from the mailbox.
wait_response:
    ldr x9, =MAILBOX_STATUS          // Reload the mailbox status register address.
    ldr w10, [x9]                    // Read the current status.
    and w10, w10, #0x40000000         // Check if the mailbox is empty.
    cbnz w10, wait_response          // Loop until data is available.
    
    // Read the response (optional verification can be done here).
    ldr x11, =MAILBOX_READ          // Load the mailbox read register address.
    ldr x12, [x11]                  // Read the mailbox response.
    ret                             // Return to the caller.


// --------------------------------------------------------------------
// Data Section: Mailbox Property Message Buffer
// We construct a mailbox message containing several tags:
//   Tag 1: Set physical display size (800x600).
//   Tag 2: Set virtual display size (800x600).
//   Tag 3: Set pixel depth (32 bits per pixel).
//   Tag 4: Allocate the framebuffer (with 16-byte alignment).
//   Tag 5: Get the pitch (bytes per row).
// The message is terminated with a zero tag.
// --------------------------------------------------------------------
    .section .data
    .align 16                      // Align the buffer to 16 bytes as required.
mailbox_buffer:
    .word 35*4                     // Total message size in bytes (35 words = 140 bytes).
    .word 0                        // Request code: 0 indicates a request.

    // Tag 1: Set physical display size.
    .word 0x48003                 // Tag ID for “set physical display size”.
    .word 8                       // Buffer size: 8 bytes (width and height).
    .word 0                       // Request code (0 for request).
    .word 800                     // Physical width in pixels.
    .word 600                     // Physical height in pixels.

    // Tag 2: Set virtual display size.
    .word 0x48004                 // Tag ID for “set virtual display size”.
    .word 8                       // Buffer size: 8 bytes.
    .word 0                       // Request code.
    .word 800                     // Virtual width in pixels.
    .word 600                     // Virtual height in pixels.

    // Tag 3: Set pixel depth.
    .word 0x48005                 // Tag ID for “set depth”.
    .word 4                       // Buffer size: 4 bytes.
    .word 0                       // Request code.
    .word 32                      // 32 bits per pixel.

    // Tag 4: Allocate framebuffer.
    .word 0x40001                 // Tag ID for “allocate framebuffer”.
    .word 8                       // Buffer size: 8 bytes.
    .word 0                       // Request code.
    .word 16                      // Alignment requirement (16 bytes).
    .word 0                       // (Response) This field will hold the framebuffer address.

    // Tag 5: Get pitch (bytes per line).
    .word 0x40008                 // Tag ID for “get pitch”.
    .word 4                       // Buffer size: 4 bytes.
    .word 0                       // Request code.
    .word 0                       // (Response) This field will be filled with the pitch.

    // End tag.
    .word 0                       // Zero tag to indicate the end of the mailbox message.

    // Pad the buffer to a total of 35 words.
    .space ((35 - 23) * 4)         // We have defined 23 words; pad the rest.


// --------------------------------------------------------------------
// Mailbox Registers Definitions (for Pi4)
// These are based on the BCM2711 datasheet. Verify these addresses for your hardware.
// --------------------------------------------------------------------
    .section .bss
    .align 4
MAILBOX_BASE:  .word 0x4000B880  // Base address for the mailbox registers.
    .section .text
    .equ MAILBOX_READ,  (MAILBOX_BASE + 0x00)    // Mailbox read register.
    .equ MAILBOX_STATUS,(MAILBOX_BASE + 0x18)     // Mailbox status register.
    .equ MAILBOX_WRITE, (MAILBOX_BASE + 0x20)      // Mailbox write register.
```

### Explanation of Key Points in `kernel.S`:

- **Entry Point (_start):**  
  The program starts at `_start`, where we immediately prepare a mailbox call to configure the display. This low-level initialization is essential in bare‑metal programming.
  
- **Mailbox Communication:**  
  The mailbox interface is the standard method on the Pi to communicate with the GPU firmware (VideoCore). We use it to set up our display parameters and to obtain the framebuffer address.
  
- **Framebuffer Filling Loop:**  
  After extracting the display width, height, pitch, and framebuffer address, we compute the number of pixels and fill the entire framebuffer with red. This loop ensures every pixel is written before the program enters an infinite loop.

- **Data Section:**  
  The `mailbox_buffer` is carefully structured to match the expected layout for a mailbox property message. Padding is added to meet the total word count expected by the firmware.

- **Mailbox Register Definitions:**  
  The mailbox register addresses are defined per the BCM2711 documentation. Always verify these addresses with the latest documentation for your specific Pi model.

---

## Linker Script (linker.ld)

Save the following as `linker.ld`. This script tells the linker where to load our program in memory. For Raspberry Pi bare‑metal kernels, a common practice is to load the code at address `0x8000` (which is where the Pi firmware expects the kernel to begin).

```ld
/* linker.ld - Linker script for bare-metal ARM AArch64 program */
ENTRY(_start)         /* Define the entry point of the program */

SECTIONS
{
  /* Set the load address to 0x8000, where the Pi firmware loads kernel images */
  . = 0x8000;

  /* Code section: contains all executable instructions */
  .text : {
    *(.text*)       /* Collect all .text sections from input files */
  }

  /* Read-only data: constants and literal strings */
  .rodata : {
    *(.rodata*)
  }

  /* Initialized data section */
  .data : {
    *(.data*)
  }

  /* Uninitialized data section */
  .bss : {
    *(.bss*)
    *(COMMON)
  }
}
```

### Explanation of Key Points in `linker.ld`:

- **ENTRY(_start):**  
  This directive tells the linker that `_start` is the entry point of the program.

- **Memory Start Address:**  
  The script sets the start address (`.`) to `0x8000` because the Raspberry Pi firmware expects the kernel image to be loaded at that address.

- **Section Grouping:**  
  All sections (code, read-only data, initialized data, and uninitialized data) are grouped so that the final binary image is contiguous and correctly organized for bare‑metal execution.

---

## Build Instructions

Follow these steps on your development machine (Linux/macOS/Windows with a suitable toolchain):

1. **Compile the Assembly Code:**

   Use the cross-compiler to assemble and link your kernel.

   ```bash
   aarch64-none-elf-gcc -nostdlib -nostartfiles -O2 -T linker.ld -o kernel8.elf kernel.S
   ```

   - **`-nostdlib -nostartfiles`:** Avoid linking standard libraries or startup code.
   - **`-O2`:** Optimize the code.
   - **`-T linker.ld`:** Use our custom linker script.
   - **`-o kernel8.elf`:** Output file in ELF format.

2. **Convert the ELF to a Raw Binary Image:**

   The Raspberry Pi firmware expects a raw binary file named `kernel8.img`.

   ```bash
   aarch64-none-elf-objcopy kernel8.elf -O binary kernel8.img
   ```

3. **Verify the Binary Size and Contents (Optional):**

   You can use tools like `hexdump` or `size` to verify that your binary looks correct.

---

## MicroSD Card Preparation and Boot Setup

1. **Partitioning and Formatting the microSD Card:**

   - **On Linux/macOS:**
     - Insert your microSD card.
     - Identify the device (e.g., `/dev/sdX`).
     - Use `fdisk` or `parted` to create a single primary partition spanning the card.
     - Format the partition as FAT32:

       ```bash
       mkfs.vfat -F 32 /dev/sdX1
       ```

       Replace `/dev/sdX1` with the actual partition identifier.

2. **Populating the Boot Partition:**

   - Copy the following files into the FAT32 boot partition:
     - **bootcode.bin**
     - **start4.elf**
     - **fixup4.dat**
   - Create or edit a `config.txt` file in the boot partition. A minimal configuration might contain:
     
     ```
     kernel=kernel8.img
     ```
     
     This tells the firmware to load your kernel image.
     
   - Copy the compiled `kernel8.img` to the boot partition.

3. **Booting Your Raspberry Pi 400:**

   - Safely eject the microSD card from your computer.
   - Insert the card into the Raspberry Pi 400.
   - Power on the Pi. The firmware will load the files from the boot partition, execute your kernel, and your program will fill the display with red.

---

## Additional Considerations

- **Display Querying:**  
  If you want to query your 7″ Elecrow display’s native resolution rather than forcing 800×600, modify your mailbox message to use a “get physical display size” tag (for example, tag `0x40003`) instead of or in addition to the “set” tags. This will have the firmware return the actual resolution of the connected display.

- **Firmware and Register Validation:**  
  Always verify the mailbox register addresses and tag IDs against the latest BCM2711 documentation for the Raspberry Pi 400. Updates in firmware or hardware revisions might require adjustments in your code.

- **Linker Script Adjustments:**  
  The load address (`0x8000`) is typical for Raspberry Pi bare‑metal projects. If you have specific memory layout requirements, adjust the linker script accordingly.
