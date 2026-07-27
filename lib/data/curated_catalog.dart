class CuratedBook {
  const CuratedBook({
    required this.id,
    required this.title,
    required this.author,
    required this.category,
    required this.description,
    required this.downloadUrl,
  });

  final String id;
  final String title;
  final String author;
  final String category;
  final String description;
  final String downloadUrl;
}

const curatedCatalog = <CuratedBook>[
  CuratedBook(
    id: 'anne-of-green-gables',
    title: 'Anne of Green Gables',
    author: 'L. M. Montgomery',
    category: 'Growing up',
    description:
        'An imaginative orphan transforms life in a quiet Canadian community.',
    downloadUrl:
        'https://standardebooks.org/ebooks/l-m-montgomery/anne-of-green-gables/downloads/l-m-montgomery_anne-of-green-gables.epub',
  ),
  CuratedBook(
    id: 'the-secret-garden',
    title: 'The Secret Garden',
    author: 'Frances Hodgson Burnett',
    category: 'Growing up',
    description:
        'A lonely girl discovers friendship, renewal, and a hidden garden.',
    downloadUrl:
        'https://standardebooks.org/ebooks/frances-hodgson-burnett/the-secret-garden/downloads/frances-hodgson-burnett_the-secret-garden.epub',
  ),
  CuratedBook(
    id: 'little-women',
    title: 'Little Women',
    author: 'Louisa May Alcott',
    category: 'Growing up',
    description:
        'Four sisters grow through ambition, hardship, family, and friendship.',
    downloadUrl:
        'https://standardebooks.org/ebooks/louisa-may-alcott/little-women/downloads/louisa-may-alcott_little-women.epub',
  ),
  CuratedBook(
    id: 'treasure-island',
    title: 'Treasure Island',
    author: 'Robert Louis Stevenson',
    category: 'Adventure',
    description:
        'Pirates, a mysterious map, and a dangerous voyage for buried treasure.',
    downloadUrl:
        'https://standardebooks.org/ebooks/robert-louis-stevenson/treasure-island/downloads/robert-louis-stevenson_treasure-island.epub',
  ),
  CuratedBook(
    id: 'white-fang',
    title: 'White Fang',
    author: 'Jack London',
    category: 'Adventure',
    description:
        'A wolf-dog travels from the wilderness toward trust and companionship.',
    downloadUrl:
        'https://standardebooks.org/ebooks/jack-london/white-fang/downloads/jack-london_white-fang.epub',
  ),
  CuratedBook(
    id: 'the-call-of-the-wild',
    title: 'The Call of the Wild',
    author: 'Jack London',
    category: 'Adventure',
    description:
        'A domestic dog confronts the brutal beauty of the Klondike wilderness.',
    downloadUrl:
        'https://standardebooks.org/ebooks/jack-london/the-call-of-the-wild/downloads/jack-london_the-call-of-the-wild.epub',
  ),
  CuratedBook(
    id: 'alice-in-wonderland',
    title: 'Alice’s Adventures in Wonderland',
    author: 'Lewis Carroll',
    category: 'Fantasy',
    description:
        'Alice follows a rabbit into a strange world of impossible characters.',
    downloadUrl:
        'https://standardebooks.org/ebooks/lewis-carroll/alices-adventures-in-wonderland/downloads/lewis-carroll_alices-adventures-in-wonderland.epub',
  ),
  CuratedBook(
    id: 'the-wonderful-wizard-of-oz',
    title: 'The Wonderful Wizard of Oz',
    author: 'L. Frank Baum',
    category: 'Fantasy',
    description:
        'Dorothy and her unusual companions cross Oz in search of the Wizard.',
    downloadUrl:
        'https://standardebooks.org/ebooks/l-frank-baum/the-wonderful-wizard-of-oz/downloads/l-frank-baum_the-wonderful-wizard-of-oz.epub',
  ),
  CuratedBook(
    id: 'peter-pan',
    title: 'Peter Pan',
    author: 'J. M. Barrie',
    category: 'Fantasy',
    description:
        'A flight to Neverland becomes an adventure with pirates and lost boys.',
    downloadUrl:
        'https://standardebooks.org/ebooks/j-m-barrie/peter-pan/downloads/j-m-barrie_peter-pan.epub',
  ),
  CuratedBook(
    id: 'sherlock-holmes',
    title: 'The Adventures of Sherlock Holmes',
    author: 'Arthur Conan Doyle',
    category: 'Mystery',
    description:
        'Twelve clever cases solved by literature’s most famous detective.',
    downloadUrl:
        'https://standardebooks.org/ebooks/arthur-conan-doyle/the-adventures-of-sherlock-holmes/downloads/arthur-conan-doyle_the-adventures-of-sherlock-holmes.epub',
  ),
  CuratedBook(
    id: 'the-time-machine',
    title: 'The Time Machine',
    author: 'H. G. Wells',
    category: 'Science fiction',
    description:
        'A scientist journeys into a distant and unsettling human future.',
    downloadUrl:
        'https://standardebooks.org/ebooks/h-g-wells/the-time-machine/downloads/h-g-wells_the-time-machine.epub',
  ),
  CuratedBook(
    id: 'dracula',
    title: 'Dracula',
    author: 'Bram Stoker',
    category: 'Horror',
    description:
        'Letters and journals reveal a desperate struggle against Count Dracula.',
    downloadUrl:
        'https://standardebooks.org/ebooks/bram-stoker/dracula/downloads/bram-stoker_dracula.epub',
  ),
];
