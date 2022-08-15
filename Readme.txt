
  Revived this old udma driver written by Jack R. Ellis to be used in Qemu,
  86Box, PCem, ...

  The driver should work both in real DOS and Win3.1 enhanced mode.
  This driver version doesn't cache and this might be an advantage
  if running in a VM, where the caching is better left to the host.

  To use it, just enter
    DEVICE=XDMA.SYS
  in file CONFIG.SYS.
  
  To create the binary, the Nasm assembler is used.  

  japheth, 08/2022.
 

