variable "identifier" {
  type = string
}

variable "workload" {
  type = map(object({
    external = bool
  }))
}