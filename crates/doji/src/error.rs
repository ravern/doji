use std::fmt::{self, Display, Formatter};

pub enum Error {
    WrongType,
}

impl Display for Error {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Self::WrongType => write!(f, "wrong type"),
        }
    }
}
