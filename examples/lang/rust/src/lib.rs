#[path = "../gugugu-generated/gugugu"]
pub mod gugugu {
  pub mod lang {
    pub mod rust {
      pub mod runtime;
    }
  }
}

#[path = "../gugugu-generated/definitions/mod.rs"]
pub mod definitions;

pub mod codec;

pub mod jsonhttp;

pub mod utils;
