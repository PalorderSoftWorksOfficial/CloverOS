return {
  id = "example_driver",

  init = function(kernel)
    kernel.info("Example driver initialized")
  end,

  shutdown = function(kernel)
    kernel.info("Example driver shutdown")
  end
}
