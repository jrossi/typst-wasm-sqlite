//! SQLite file format constants and structures

/// SQLite file header magic string
pub const SQLITE_HEADER_MAGIC: &[u8; 16] = b"SQLite format 3\0";

/// Minimum size for a valid SQLite database (header size)
pub const MIN_DATABASE_SIZE: usize = 100;

/// SQLite file header structure (first 100 bytes)
#[derive(Debug, Clone)]
pub struct FileHeader {
    /// Page size in bytes (16-bit at offset 16, or 1 means 65536)
    pub page_size: u32,
    /// File format write version (1 = legacy, 2 = WAL)
    pub write_version: u8,
    /// File format read version
    pub read_version: u8,
    /// Reserved space at end of each page
    pub reserved_space: u8,
    /// Size of database in pages
    pub database_size: u32,
    /// Text encoding (1 = UTF-8, 2 = UTF-16le, 3 = UTF-16be)
    pub text_encoding: u32,
}

impl FileHeader {
    /// Parse header from bytes (must be at least 100 bytes)
    pub fn parse(data: &[u8]) -> Option<Self> {
        if data.len() < 100 {
            return None;
        }

        // Check magic
        if &data[0..16] != SQLITE_HEADER_MAGIC {
            return None;
        }

        // Page size is at offset 16-17 (big-endian)
        let page_size_raw = u16::from_be_bytes([data[16], data[17]]);
        let page_size = if page_size_raw == 1 {
            65536u32
        } else {
            page_size_raw as u32
        };

        let write_version = data[18];
        let read_version = data[19];
        let reserved_space = data[20];

        // Database size in pages is at offset 28-31 (big-endian)
        let database_size = u32::from_be_bytes([data[28], data[29], data[30], data[31]]);

        // Text encoding at offset 56-59
        let text_encoding = u32::from_be_bytes([data[56], data[57], data[58], data[59]]);

        Some(FileHeader {
            page_size,
            write_version,
            read_version,
            reserved_space,
            database_size,
            text_encoding,
        })
    }
}

/// Page types in SQLite
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PageType {
    /// Interior index b-tree page
    InteriorIndex = 0x02,
    /// Interior table b-tree page
    InteriorTable = 0x05,
    /// Leaf index b-tree page
    LeafIndex = 0x0a,
    /// Leaf table b-tree page
    LeafTable = 0x0d,
}

impl PageType {
    pub fn from_byte(byte: u8) -> Option<Self> {
        match byte {
            0x02 => Some(PageType::InteriorIndex),
            0x05 => Some(PageType::InteriorTable),
            0x0a => Some(PageType::LeafIndex),
            0x0d => Some(PageType::LeafTable),
            _ => None,
        }
    }

    pub fn is_leaf(&self) -> bool {
        matches!(self, PageType::LeafIndex | PageType::LeafTable)
    }

    pub fn is_table(&self) -> bool {
        matches!(self, PageType::InteriorTable | PageType::LeafTable)
    }
}

/// B-tree page header
#[derive(Debug, Clone)]
pub struct BTreePageHeader {
    pub page_type: PageType,
    pub first_freeblock: u16,
    pub cell_count: u16,
    pub cell_content_start: u16,
    pub fragmented_free_bytes: u8,
    /// Only present for interior pages
    pub right_child: Option<u32>,
}

impl BTreePageHeader {
    /// Parse B-tree page header
    /// `is_first_page` indicates if this is page 1 (which has 100 byte file header)
    pub fn parse(data: &[u8], is_first_page: bool) -> Option<Self> {
        let offset = if is_first_page { 100 } else { 0 };

        if data.len() < offset + 8 {
            return None;
        }

        let page_type = PageType::from_byte(data[offset])?;

        let first_freeblock = u16::from_be_bytes([data[offset + 1], data[offset + 2]]);
        let cell_count = u16::from_be_bytes([data[offset + 3], data[offset + 4]]);
        let cell_content_start = u16::from_be_bytes([data[offset + 5], data[offset + 6]]);
        let fragmented_free_bytes = data[offset + 7];

        let right_child = if !page_type.is_leaf() {
            if data.len() < offset + 12 {
                return None;
            }
            Some(u32::from_be_bytes([
                data[offset + 8],
                data[offset + 9],
                data[offset + 10],
                data[offset + 11],
            ]))
        } else {
            None
        };

        Some(BTreePageHeader {
            page_type,
            first_freeblock,
            cell_count,
            cell_content_start,
            fragmented_free_bytes,
            right_child,
        })
    }

    /// Get the size of the header in bytes
    pub fn header_size(&self) -> usize {
        if self.page_type.is_leaf() {
            8
        } else {
            12
        }
    }
}
